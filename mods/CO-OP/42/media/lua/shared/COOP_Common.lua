--
-- CO-OP - shared helpers for the mod as a whole.
--
-- Feature modules keep their own prefixes (BAH_* for the "books at home" list);
-- anything used by more than one feature belongs here.
--

COOP = COOP or {}

function COOP.log(_msg)
    print("[CO-OP] " .. tostring(_msg))
end

-- The name to credit an action to: the multiplayer username, else the character's
-- forename. "?" when neither can be read.
function COOP.playerName(_playerObj)
    if _playerObj == nil then return "?" end

    local okUser, user = pcall(function() return _playerObj:getUsername() end)
    if okUser and user and user ~= "" then return tostring(user) end

    local okDesc, forename = pcall(function() return _playerObj:getDescriptor():getForename() end)
    if okDesc and forename and forename ~= "" then return tostring(forename) end

    return "?"
end

-- In-game calendar stamp, e.g. "12/07/1993 14:20". Safe to call from either side.
function COOP.gameDateString()
    local ok, stamp = pcall(function()
        local gt = getGameTime()
        return string.format("%02d/%02d/%d %02d:%02d",
                gt:getDay() + 1, gt:getMonth() + 1, gt:getYear(),
                gt:getHour(), gt:getMinutes())
    end)
    if ok and stamp then return stamp end
    return "?"
end

-- Monotonic in-game hours, for sorting things into the order they happened.
function COOP.worldAgeHours()
    local ok, hours = pcall(function() return getGameTime():getWorldAgeHours() end)
    if ok and hours then return hours end
    return 0
end

-- ---------------------------------------------------------------------------
-- sandbox options
--
-- Everything tunable lives in media/sandbox-options.txt under the COOP namespace, so a
-- server admin can change it without touching the mod. SandboxVars is not populated
-- until the world loads and, on a multiplayer client, it arrives from the server - so
-- these are read at the moment they are needed, never cached at file load, and every
-- one falls back to the value the mod would have used before options existed.
-- ---------------------------------------------------------------------------

COOP.OPTIONS = "COOP"

-- feature switches
COOP.F_BOOKS = "BooksAtHome"
COOP.F_MAPSHARE = "MapShare"
COOP.F_OUTPUT = "ItemOutput"
COOP.F_ORGANIZATION = "Organization"
COOP.F_PINGS = "Pings"
COOP.F_TODO = "Todo"
COOP.F_HOTBAR = "HotbarStatus"

function COOP.option(_name, _default)
    local ok, value = pcall(function()
        local vars = SandboxVars and SandboxVars[COOP.OPTIONS]
        if vars == nil then return nil end
        return vars[_name]
    end)
    if ok and value ~= nil then return value end
    return _default
end

function COOP.numberOption(_name, _default, _min, _max)
    local value = tonumber(COOP.option(_name, _default))
    if value == nil or value ~= value then return _default end
    if _min ~= nil and value < _min then return _min end
    if _max ~= nil and value > _max then return _max end
    return value
end

-- Features are on unless the server turned them off.
function COOP.featureEnabled(_name)
    return COOP.option(_name, true) ~= false
end
