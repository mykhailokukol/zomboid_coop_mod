--
-- CO-OP - AFK: the rules both sides share, and the freeze itself.
--
-- A player who presses AFK and then stands still for AfkDelay seconds is frozen until
-- they do anything at all: hunger, thirst, tiredness, moods, wounds, bandages, illness
-- and zombie infection all stop where they were, the TV and the radio stop teaching
-- them, and other players cannot treat, wake or trade with them. A badge over the
-- character says so to everyone.
--
-- B42 runs a multiplayer character's body on the server - BodyDamage.Update returns at
-- once on a client for a local player, and the server pushes the stats down to it in
-- NetworkPlayerAI.syncStats - so the freeze has to run on the server. In single
-- player the same functions run in the one Lua state there is.
--
-- There is no engine switch for "stop simulating this character". calculateStats is
-- skipped when the CalculateStats Lua hook has a callback, but LuaHookManager's trigger
-- answers true for *any* registered callback, so one hook would freeze everybody, and
-- the god mode / zombies-don't-attack cheats are admin capabilities that heal rather
-- than freeze. So the freeze is a snapshot, taken when the player goes AFK and written
-- back every tick while they stay AFK. Within a tick nothing moves far enough to show.
--

require "COOP_Common"

COOPAfk = COOPAfk or {}

COOPAfk.MODULE = "CO-OP"

COOPAfk.CMD_ON = "afkOn"
COOPAfk.CMD_OFF = "afkOff"
COOPAfk.CMD_REQUEST_SYNC = "afkRequestSync"
COOPAfk.CMD_SYNC = "afkSync"
COOPAfk.CMD_STATE = "afkState"

-- why an AFK ended, carried in CMD_STATE so the player is told the right thing
COOPAfk.R_BACK = "back"        -- they did something, or pressed the button again
COOPAfk.R_HURT = "hurt"        -- something hit them
COOPAfk.R_MOVED = "moved"      -- the server saw them move off the spot
COOPAfk.R_GONE = "gone"        -- disconnected or died
COOPAfk.R_OFF = "off"          -- the feature was switched off
COOPAfk.R_REFUSED = "refused"  -- asked to go AFK and the server said no

COOPAfk.DEFAULT_DELAY = 10

-- Drift from the spot the player went AFK on that counts as walking away from it. The
-- client cancels on much less; this is the server's own check on a client that never
-- sends "I moved".
COOPAfk.SERVER_MOVE_LIMIT = 1.5

-- Per tick, a body part losing more health than this, or any wound timer going *up*,
-- is a hit and not the slow drift of time. Time only ever heals a timer downwards.
COOPAfk.HIT_HEALTH = 3

function COOPAfk.isEnabled()
    return COOP.featureEnabled(COOP.F_AFK)
end

function COOPAfk.delaySeconds()
    return math.floor(COOP.numberOption("AfkDelay", COOPAfk.DEFAULT_DELAY, 3, 60))
end

-- ---------------------------------------------------------------------------
-- who is AFK
--
-- Name -> true. On the server and in single player this is the authority's table; on a
-- multiplayer client it is the cache the server's deltas keep. Both are this one table,
-- so isAfk reads the same everywhere.
-- ---------------------------------------------------------------------------

COOPAfk.names = COOPAfk.names or {}

-- Kahlua has no global next(), so "is this table empty" is a pairs loop.
function COOPAfk.isEmpty(_table)
    for _ in pairs(_table) do return false end
    return true
end

function COOPAfk.isAfkName(_name)
    if _name == nil then return false end
    return COOPAfk.names[_name] == true
end

function COOPAfk.isAfk(_player)
    if _player == nil then return false end
    if not COOPAfk.isEnabled() then return false end
    return COOPAfk.isAfkName(COOP.playerName(_player))
end

-- Every player this Lua state can see: the online list in multiplayer (on the server
-- and on a client alike), the local players otherwise.
function COOPAfk.eachPlayer(_fn)
    local list = nil
    if isClient() or isServer() then
        pcall(function() list = getOnlinePlayers() end)
    end
    if list ~= nil then
        for i = 0, list:size() - 1 do
            local player = list:get(i)
            if player ~= nil then _fn(player) end
        end
        return
    end
    for i = 0, 3 do
        local player = getSpecificPlayer(i)
        if player ~= nil then _fn(player) end
    end
end

function COOPAfk.findPlayer(_name)
    local found = nil
    COOPAfk.eachPlayer(function(_player)
        if found == nil and COOP.playerName(_player) == _name then found = _player end
    end)
    return found
end

-- ---------------------------------------------------------------------------
-- the snapshot
--
-- Everything is read and written by method name through pcall, so a getter that a
-- later build renames costs that one value and nothing else.
-- ---------------------------------------------------------------------------

local STAT_NAMES = {
    "ANGER", "BOREDOM", "DISCOMFORT", "ENDURANCE", "FATIGUE", "FITNESS",
    "FOOD_SICKNESS", "HUNGER", "IDLENESS", "INTOXICATION", "MORALE",
    "NICOTINE_WITHDRAWAL", "PAIN", "PANIC", "POISON", "SANITY", "SICKNESS", "STRESS",
    "TEMPERATURE", "THIRST", "UNHAPPINESS", "WETNESS", "ZOMBIE_FEVER", "ZOMBIE_INFECTION",
}

local NUTRITION_FIELDS = {
    { "getCalories", "setCalories" },
    { "getCarbohydrates", "setCarbohydrates" },
    { "getLipids", "setLipids" },
    { "getProteins", "setProteins" },
    { "getWeight", "setWeight" },
}

-- Whole-body timers: catching a cold, the meal-healing timer, painkillers wearing off.
local BODY_FIELDS = {
    { "getColdStrength", "setColdStrength" },
    { "getCatchACold", "setCatchACold" },
    { "getHealthFromFoodTimer", "setHealthFromFoodTimer" },
    { "getPainReduction", "setPainReduction" },
    { "getColdReduction", "setColdReduction" },
}

-- The wound timers. Each one only ever counts down as a wound heals, so one going up
-- means a fresh wound - that is how a hit is told apart from time passing. The setters
-- are plain field writes (setBleedingTime also re-derives the bleeding flag from the
-- value, which is what restoring it should do).
local WOUND_FIELDS = {
    { "getScratchTime", "setScratchTime" },
    { "getCutTime", "setCutTime" },
    { "getBiteTime", "setBiteTime" },
    { "getDeepWoundTime", "setDeepWoundTime" },
    { "getFractureTime", "setFractureTime" },
    { "getBurnTime", "setBurnTime" },
    { "getBleedingTime", "setBleedingTime" },
}

-- Per-part values that move with time and are restored, but are no evidence of a hit.
local PART_FIELDS = {
    { "getHealth", "SetHealth" },
    { "getBandageLife", "setBandageLife" },
    { "getStitchTime", "setStitchTime" },
    { "getWoundInfectionLevel", "setWoundInfectionLevel" },
    { "getAdditionalPain", "setAdditionalPain" },
    { "getStiffness", "setStiffness" },
    { "getWetness", "setWetness" },
    { "getAlcoholLevel", "setAlcoholLevel" },
    { "getPlantainFactor", "setPlantainFactor" },
    { "getComfreyFactor", "setComfreyFactor" },
    { "getGarlicFactor", "setGarlicFactor" },
    { "getSplintFactor", "setSplintFactor" },
}

local function read(_object, _getter)
    local ok, value = pcall(function() return _object[_getter](_object) end)
    if ok and type(value) == "number" then return value end
    return nil
end

local function write(_object, _setter, _value)
    pcall(function() _object[_setter](_object, _value) end)
end

local function readFields(_object, _fields)
    local out = {}
    if _object == nil then return out end
    for i, field in ipairs(_fields) do out[i] = read(_object, field[1]) end
    return out
end

-- Writes back only what changed, so an untouched value never goes through its setter.
local function restoreFields(_object, _fields, _saved)
    if _object == nil or _saved == nil then return end
    for i, field in ipairs(_fields) do
        local want = _saved[i]
        if want ~= nil then
            local now = read(_object, field[1])
            if now ~= nil and now ~= want then write(_object, field[2], want) end
        end
    end
end

local function bodyParts(_player)
    local parts = {}
    pcall(function()
        local list = _player:getBodyDamage():getBodyParts()
        for i = 0, list:size() - 1 do parts[i + 1] = list:get(i) end
    end)
    return parts
end

local function hoursSurvived(_player)
    return read(_player, "getHoursSurvived") or 0
end

function COOPAfk.snapshot(_player)
    local snap = { stats = {}, parts = {} }

    pcall(function()
        local stats = _player:getStats()
        for _, name in ipairs(STAT_NAMES) do
            local stat = CharacterStat[name]
            if stat ~= nil then
                local ok, value = pcall(function() return stats:get(stat) end)
                if ok and type(value) == "number" then snap.stats[name] = value end
            end
        end
    end)

    pcall(function() snap.nutrition = readFields(_player:getNutrition(), NUTRITION_FIELDS) end)
    pcall(function() snap.body = readFields(_player:getBodyDamage(), BODY_FIELDS) end)
    snap.overall = read(_player:getBodyDamage(), "getOverallBodyHealth")

    for i, part in ipairs(bodyParts(_player)) do
        snap.parts[i] = {
            wounds = readFields(part, WOUND_FIELDS),
            values = readFields(part, PART_FIELDS),
        }
    end

    snap.hours = hoursSurvived(_player)
    return snap
end

-- True when the character has been hurt since the snapshot: a wound timer went up, or
-- a part lost more health in one tick than time takes from it.
function COOPAfk.wasHurt(_player, _snap)
    if _snap == nil then return false end
    for i, part in ipairs(bodyParts(_player)) do
        local saved = _snap.parts[i]
        if saved ~= nil then
            for k, field in ipairs(WOUND_FIELDS) do
                local before = saved.wounds[k]
                local now = read(part, field[1])
                if before ~= nil and now ~= nil and now > before + 0.001 then return true end
            end
            local before = saved.values[1]
            local now = read(part, "getHealth")
            if before ~= nil and now ~= nil and before - now > COOPAfk.HIT_HEALTH then return true end
        end
    end
    return false
end

-- Writes the snapshot back. Called every tick on the authoritative side.
function COOPAfk.restore(_player, _snap)
    if _snap == nil then return end

    pcall(function()
        local stats = _player:getStats()
        for name, value in pairs(_snap.stats) do
            local stat = CharacterStat[name]
            if stat ~= nil and stats:get(stat) ~= value then stats:set(stat, value) end
        end
    end)

    pcall(function() restoreFields(_player:getNutrition(), NUTRITION_FIELDS, _snap.nutrition) end)

    local body = nil
    pcall(function() body = _player:getBodyDamage() end)
    if body == nil then return end

    restoreFields(body, BODY_FIELDS, _snap.body)
    for i, part in ipairs(bodyParts(_player)) do
        local saved = _snap.parts[i]
        if saved ~= nil then
            restoreFields(part, WOUND_FIELDS, saved.wounds)
            restoreFields(part, PART_FIELDS, saved.values)
        end
    end
    if _snap.overall ~= nil and read(body, "getOverallBodyHealth") ~= _snap.overall then
        write(body, "setOverallBodyHealth", _snap.overall)
    end

    -- Zombie infection is not a stored number but a clock: BodyDamage works out how far
    -- along it is from getHoursSurvived() - getInfectionTime(). Holding the stat alone
    -- would only hide the progress until the AFK ended, so the infection's start is
    -- moved forward by exactly the time that has passed.
    local hours = hoursSurvived(_player)
    local passed = hours - (_snap.hours or hours)
    _snap.hours = hours
    if passed > 0 then
        pcall(function()
            if body:IsInfected() then
                body:setInfectionTime(body:getInfectionTime() + passed)
            end
        end)
    end
end

-- ---------------------------------------------------------------------------
-- TV, radio and CDs
--
-- Every broadcast line goes through ISRadioInteractions' checkPlayer, which applies its
-- codes (skill XP, boredom, recipes) and marks the line as heard. An AFK player is
-- skipped before any of that, so the line is still new to them when they come back.
-- It is called through the instance table (self.checkPlayer), so replacing the field
-- is enough. Runs wherever the radio runs: the server in multiplayer, the client in
-- single player.
-- ---------------------------------------------------------------------------

local radioWrapped = nil

local function wrapRadio()
    if ISRadioInteractions == nil then return end
    local ok, instance = pcall(function() return ISRadioInteractions:getInstance() end)
    if not ok or instance == nil then return end
    if radioWrapped ~= nil and instance.checkPlayer == radioWrapped then return end

    local original = instance.checkPlayer
    if original == nil then return end

    radioWrapped = function(player, ...)
        if COOPAfk.isAfk(player) then return end
        return original(player, ...)
    end
    instance.checkPlayer = radioWrapped
end

Events.OnGameBoot.Add(wrapRadio)
Events.OnGameStart.Add(wrapRadio)
if Events.OnServerStarted then Events.OnServerStarted.Add(wrapRadio) end
