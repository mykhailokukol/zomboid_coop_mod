--
-- CO-OP - the "Organization" skill.
--
-- A custom perk that generalises the vanilla Organized / Disorganized traits:
--
--   level  0    1     2     3     4     5     6     7     8     9    10
--   mult  50%  67%   83%  100%  117%  133%  150%  175%  200%  225%  250%
--
-- Everyone starts at 3 (vanilla). Organized starts at 6, Disorganized at 0, and the
-- trait itself is removed so its own effect cannot stack on top. XP comes from the
-- weight of items moved in and out of containers.
--
-- What the level actually does:
--   * capacity - a container the player opens is raised to base * multiplier, and
--     never lowered: a crate organised by a level 10 player stays big for everyone.
--     Per-player capacity is impossible, the vanilla trait effect lives inside
--     ItemContainer.getEffectiveCapacity (Java) where Lua cannot reach it.
--   * speed - the server computes item-move duration in Java (zombie/core/Transaction)
--     and only honours the Dextrous / All Thumbs traits, so the perk manages those:
--     level 6+ is Dextrous (x2 faster), level 0-1 is All Thumbs (x2 slower).
--

require "COOP_Common"

COOPOrg = COOPOrg or {}

COOPOrg.PERK_NAME = "Organization"
-- The skills panel only lists perks that have a category parent: ISCharacterInfo
-- skips anything whose parent is Perks.None. "Crafting" puts it next to the other
-- utility skills; change this to move it elsewhere in the panel.
COOPOrg.PARENT_NAME = "Crafting"
COOPOrg.MODULE = "CO-OP"
COOPOrg.CMD_CAPACITY = "orgCapacity"
COOPOrg.CMD_LEVEL = "orgLevel"

COOPOrg.DEFAULT_LEVEL = 3
COOPOrg.ORGANIZED_LEVEL = 6
COOPOrg.DISORGANIZED_LEVEL = 0

COOPOrg.FAST_LEVEL = 6   -- at or above: Dextrous
COOPOrg.SLOW_LEVEL = 1   -- at or below: All Thumbs

COOPOrg.XP_PER_KG = 10   -- base XP for one kilogram moved; the sandbox rate scales it
COOPOrg.debug = false    -- set true to trace XP and capacity changes in the console
COOPOrg.XP_LEVELS = { 75, 150, 300, 750, 1500, 3000, 6000, 12000, 24000, 48000 }

COOPOrg.BASE_CAPACITY_KEY = "COOP_OrgBaseCapacity"
COOPOrg.INIT_KEY = "COOP_OrgInit"
COOPOrg.START_LEVEL_KEY = "COOP_OrgStartLevel"
COOPOrg.XP_KEY = "COOP_OrgXp"

-- linear between the anchors 0 = 50%, 3 = 100%, 6 = 150%, 10 = 250%
COOPOrg.MULTIPLIER = {
    [0] = 0.50, [1] = 0.667, [2] = 0.833, [3] = 1.00, [4] = 1.167, [5] = 1.333,
    [6] = 1.50, [7] = 1.75, [8] = 2.00, [9] = 2.25, [10] = 2.50,
}

-- ---------------------------------------------------------------------------
-- the perk
-- ---------------------------------------------------------------------------

-- PerkFactory lives in Java and survives a Lua state reload, while this file is re-run
-- every time (main menu -> in game, and again when another file requires it). Asking
-- the factory is therefore the only reliable "did we already do this?" - a local flag
-- let the perk be registered once per Lua state, which is how four Organization rows
-- ended up in the skills panel, each with its own id and its own (empty) XP.
local function describePerk(_perk)
    if _perk == nil then return "nil" end
    local ok, text = pcall(function()
        return tostring(_perk:getName()) .. "#" .. tostring(_perk:getId())
    end)
    if ok then return text end
    return "?"
end

function COOPOrg.dumpPerks()
    pcall(function()
        local list = PerkFactory.PerkList
        if list == nil then COOP.log("PerkList is nil"); return end
        local names = {}
        for i = 0, list:size() - 1 do
            table.insert(names, describePerk(list:get(i)))
        end
        COOP.log("PerkList: " .. table.concat(names, ", "))
    end)
end

local function findRegisteredPerk()
    local byName = nil
    pcall(function() byName = PerkFactory.getPerkFromName(COOPOrg.PERK_NAME) end)
    if byName ~= nil then return byName end

    local ok, found = pcall(function()
        local list = PerkFactory.PerkList
        if list == nil then return nil end

        local wanted = { [COOPOrg.PERK_NAME] = true }
        local translated = getText("IGUI_perks_" .. COOPOrg.PERK_NAME)
        if translated ~= nil and translated ~= "" then wanted[translated] = true end

        for i = 0, list:size() - 1 do
            local perk = list:get(i)
            if perk ~= nil and wanted[perk:getName()] == true then return perk end
        end
        return nil
    end)
    if ok then return found end
    return nil
end

-- The perk everything else must use: the one actually in the factory, so XP, the skills
-- panel and getPerkLevel all talk about the same object.
function COOPOrg.getPerk()
    if COOPOrg.perk ~= nil then return COOPOrg.perk end

    local found = findRegisteredPerk()
    if found ~= nil then
        COOPOrg.perk = found
        return found
    end

    local ok, perk = pcall(function() return Perks.FromString(COOPOrg.PERK_NAME) end)
    if ok then return perk end
    return nil
end

function COOPOrg.register()
    local existing = findRegisteredPerk()
    if existing ~= nil then
        COOPOrg.perk = existing
        if COOPOrg.debug then
            COOP.log("Organization perk already in the factory as " .. describePerk(existing))
        end
        return
    end

    local xp = COOPOrg.XP_LEVELS

    -- Perks.FromString on an unknown name hands back the MAX sentinel, not a new perk,
    -- and AddPerk simply renames whatever it is given - a perk whose id stays "MAX" is
    -- never tracked on a character, so its level reads 0 forever. Try to hand AddPerk a
    -- genuinely fresh Perk object instead.
    local perk = nil
    local source = "none"
    pcall(function() perk = PerkFactory.Perk.new(); source = "PerkFactory.Perk.new()" end)
    if perk == nil then
        pcall(function() perk = Perk.new(); source = "Perk.new()" end)
    end
    if perk == nil then
        pcall(function() perk = Perks.FromString(COOPOrg.PERK_NAME); source = "Perks.FromString" end)
    end
    if perk == nil then
        -- happens on the very first Lua state at boot; the event retries handle it
        return
    end
    COOP.log("creating the Organization perk via " .. source .. ": " .. describePerk(perk))

    local parent = nil
    local okParent = pcall(function() parent = Perks.FromString(COOPOrg.PARENT_NAME) end)
    if not okParent or parent == nil then
        COOP.log("no '" .. COOPOrg.PARENT_NAME .. "' category to hang the perk on")
        return
    end

    local created = nil
    local ok, err = pcall(function()
        created = PerkFactory.AddPerk(perk, COOPOrg.PERK_NAME, parent,
                xp[1], xp[2], xp[3], xp[4], xp[5], xp[6], xp[7], xp[8], xp[9], xp[10], false)
    end)

    if not ok then
        COOP.log("could not register the Organization perk: " .. tostring(err))
        return
    end

    COOPOrg.perk = created or findRegisteredPerk() or perk
    COOP.log("Organization perk registered under " .. COOPOrg.PARENT_NAME
            .. " as " .. describePerk(COOPOrg.perk)
            .. " (AddPerk returned " .. describePerk(created) .. ")")

    -- The perk is a label for the skills panel; the level behind it is ours.
    if COOPOrg.debug then COOPOrg.dumpPerks() end
end

-- ---------------------------------------------------------------------------
-- XP and level, kept by the mod
--
-- The engine cannot hold a modded skill: Perks is a fixed Java enum, Perks.FromString
-- returns the MAX sentinel for an unknown name, and AddPerk only renames it. A perk
-- whose id is "MAX" is never tracked on a character, so getPerkLevel always answers 0.
-- The perk still gets registered, but only so the skills panel has a row to draw - the
-- number behind it lives in the character's mod data.
-- ---------------------------------------------------------------------------

function COOPOrg.totalXpForLevel(_level)
    local total = 0
    for i = 1, math.min(_level, #COOPOrg.XP_LEVELS) do
        total = total + COOPOrg.XP_LEVELS[i]
    end
    return total
end

function COOPOrg.levelFromXp(_xp)
    local xp = _xp or 0
    for level = 10, 1, -1 do
        if xp >= COOPOrg.totalXpForLevel(level) then return level end
    end
    return 0
end

function COOPOrg.getXp(_character)
    if _character == nil then return 0 end
    local ok, xp = pcall(function() return _character:getModData()[COOPOrg.XP_KEY] end)
    if ok and type(xp) == "number" then return xp end
    return 0
end

function COOPOrg.setXp(_character, _xp)
    if _character == nil then return end
    pcall(function() _character:getModData()[COOPOrg.XP_KEY] = _xp end)
end

-- Returns the new level and whether it just went up.
function COOPOrg.addXp(_character, _amount)
    if _character == nil or _amount == nil or _amount <= 0 then return nil, false end

    local before = COOPOrg.getLevel(_character)
    local xp = COOPOrg.getXp(_character) + _amount

    local cap = COOPOrg.totalXpForLevel(10)
    if xp > cap then xp = cap end

    COOPOrg.setXp(_character, xp)

    local after = COOPOrg.levelFromXp(xp)
    return after, after > before
end

-- XP into the current level, and what the level costs.
function COOPOrg.getProgress(_character)
    local level = COOPOrg.getLevel(_character)
    if level >= 10 then return 1, 1 end

    local floor = COOPOrg.totalXpForLevel(level)
    local needed = COOPOrg.XP_LEVELS[level + 1] or 0
    local into = COOPOrg.getXp(_character) - floor
    if into < 0 then into = 0 end
    if needed <= 0 then return 1, 1 end
    return into, needed
end

function COOPOrg.getLevel(_character)
    if _character == nil then return COOPOrg.DEFAULT_LEVEL end
    return COOPOrg.levelFromXp(COOPOrg.getXp(_character))
end

function COOPOrg.getMultiplier(_character)
    -- 1.0 is "no effect", and requestCapacity already declines to ask for that, so this
    -- one line switches the capacity half of the perk off
    if not COOP.featureEnabled(COOP.F_ORGANIZATION) then return 1.0 end
    return COOPOrg.MULTIPLIER[COOPOrg.getLevel(_character)] or 1.0
end

-- ---------------------------------------------------------------------------
-- traits (the only lever the server's Java transfer timer honours)
-- ---------------------------------------------------------------------------

function COOPOrg.applyTraits(_character, _level)
    if _character == nil then return end
    if not COOP.featureEnabled(COOP.F_ORGANIZATION) then return end

    local ok, err = pcall(function()
        local traits = _character:getCharacterTraits()
        if traits == nil then return end

        local wantFast = _level >= COOPOrg.FAST_LEVEL
        local wantSlow = _level <= COOPOrg.SLOW_LEVEL

        local hasFast = _character:hasTrait(CharacterTrait.DEXTROUS)
        local hasSlow = _character:hasTrait(CharacterTrait.ALL_THUMBS)

        if wantFast and not hasFast then traits:add(CharacterTrait.DEXTROUS) end
        if not wantFast and hasFast then traits:remove(CharacterTrait.DEXTROUS) end
        if wantSlow and not hasSlow then traits:add(CharacterTrait.ALL_THUMBS) end
        if not wantSlow and hasSlow then traits:remove(CharacterTrait.ALL_THUMBS) end
    end)

    if not ok then COOP.log("could not update Organization traits: " .. tostring(err)) end
end

-- ---------------------------------------------------------------------------
-- container capacity
-- ---------------------------------------------------------------------------

-- Where the untouched capacity is remembered, so repeated raises never compound.
local function baseCapacityHolder(_container)
    local item = _container:getContainingItem()
    if item ~= nil then return item:getModData(), COOPOrg.BASE_CAPACITY_KEY end

    local object = _container:getParent()
    if object ~= nil then
        local index = object:getContainerIndex(_container)
        return object:getModData(), COOPOrg.BASE_CAPACITY_KEY .. "_" .. tostring(index)
    end

    return nil, nil
end

-- Read-only: the remembered original capacity, or nil if this container was never
-- raised. Safe to call from render code, unlike getBaseCapacity which records it.
function COOPOrg.peekBaseCapacity(_container)
    if _container == nil then return nil end
    local ok, base = pcall(function()
        local holder, key = baseCapacityHolder(_container)
        if holder == nil then return nil end
        return holder[key]
    end)
    if ok then return base end
    return nil
end

function COOPOrg.getBaseCapacity(_container)
    local holder, key = baseCapacityHolder(_container)
    local capacity = _container:getCapacity()
    if holder == nil then return capacity end

    if holder[key] == nil then
        holder[key] = capacity
        return capacity
    end
    return holder[key]
end

-- The capacity this container should have at that multiplier, or nil when it is
-- already at least that big. Capacity only ever goes up.
--
-- This must only ever run where the base capacity is recorded - the server in MP. A
-- client that has not seen the base treats the already-raised capacity as the base and
-- multiplies again on every open, which is how a level 6 crate grew past 200%.
function COOPOrg.wantedCapacity(_container, _multiplier)
    if _container == nil or _multiplier == nil then return nil, nil end
    -- a cart already holds the most any item container can (see COOP_Cart.lua)
    if COOPCart ~= nil and COOPCart.isCartContainer(_container) then
        COOPCart.trace("organization: left the cart's capacity alone (%s)", tostring(_container:getCapacity()))
        return nil, nil
    end

    local ok, wanted, base = pcall(function()
        local recorded = COOPOrg.getBaseCapacity(_container)
        if recorded == nil or recorded <= 0 then return nil, nil end

        local target = math.floor(recorded * _multiplier + 0.5)
        if target < recorded then target = recorded end

        local current = _container:getCapacity()

        -- A capacity no level could ever grant is left over from the compounding bug,
        -- where the raise was worked out from an already-raised number. Put it back.
        local ceiling = math.floor(recorded * COOPOrg.MULTIPLIER[10] + 0.5)
        if current > ceiling then
            COOP.log("repairing an over-inflated container: " .. tostring(current)
                    .. " -> " .. tostring(target) .. " (base " .. tostring(recorded) .. ")")
            return target, recorded
        end

        if target <= current then return nil, recorded end
        return target, recorded
    end)

    if ok then return wanted, base end
    return nil, nil
end

-- Remembers what a container held before anyone organised it, so the readout and any
-- later raise work from the true original.
function COOPOrg.rememberBaseCapacity(_container, _base)
    if _container == nil or _base == nil then return end
    pcall(function()
        local holder, key = baseCapacityHolder(_container)
        if holder ~= nil then holder[key] = _base end
    end)
end

function COOPOrg.setCapacity(_container, _capacity)
    if _container == nil or _capacity == nil then return false end
    local ok, err = pcall(function()
        COOPOrg.getBaseCapacity(_container)  -- make sure the original is remembered first
        _container:setCapacity(_capacity)
    end)
    if not ok then
        COOP.log("could not raise container capacity: " .. tostring(err))
        return false
    end
    return true
end

-- Finds the container a capacity message is about, on whichever side receives it.
function COOPOrg.resolveContainer(_args, _character)
    if _args == nil then return nil end

    local ok, container = pcall(function()
        if _args.itemId ~= nil and _character ~= nil then
            local item = _character:getInventory():getItemById(_args.itemId)
            if item ~= nil then return item:getInventory() end
            return nil
        end

        if _args.x == nil or _args.y == nil or _args.z == nil then return nil end
        local square = getCell():getGridSquare(_args.x, _args.y, _args.z)
        if square == nil then return nil end

        local objects = square:getObjects()
        if _args.objectIndex ~= nil and _args.objectIndex < objects:size() then
            local object = objects:get(_args.objectIndex)
            if object ~= nil then
                local found = object:getContainerByIndex(_args.containerIndex or 0)
                if found ~= nil then return found end
            end
        end

        for i = 0, objects:size() - 1 do
            local object = objects:get(i)
            for j = 0, object:getContainerCount() - 1 do
                local candidate = object:getContainerByIndex(j)
                if candidate ~= nil and (_args.containerType == nil
                        or candidate:getType() == _args.containerType) then
                    return candidate
                end
            end
        end
        return nil
    end)

    if ok then return container end
    return nil
end

-- ---------------------------------------------------------------------------
-- multiplayer plumbing
-- ---------------------------------------------------------------------------

local function onClientCommand(_module, _command, _playerObj, _args)
    if _module ~= COOPOrg.MODULE then return end

    if _command == COOPOrg.CMD_CAPACITY then
        local container = COOPOrg.resolveContainer(_args, _playerObj)
        if container == nil or _args.multiplier == nil then return end

        local wanted, base = COOPOrg.wantedCapacity(container, _args.multiplier)
        if wanted == nil then return end
        if not COOPOrg.setCapacity(container, wanted) then return end

        -- everyone needs the new number, and the original so their readout is right
        _args.capacity = wanted
        _args.base = base
        sendServerCommand(COOPOrg.MODULE, COOPOrg.CMD_CAPACITY, _args)

    elseif _command == COOPOrg.CMD_LEVEL then
        -- the server's own copy of the character carries the traits the Java transfer
        -- timer reads, and its mod data is what actually gets saved, so both live here
        if _args.xp ~= nil then COOPOrg.setXp(_playerObj, _args.xp) end
        pcall(function()
            local modData = _playerObj:getModData()
            if _args.init ~= nil then modData[COOPOrg.INIT_KEY] = _args.init end
            if _args.startLevel ~= nil then modData[COOPOrg.START_LEVEL_KEY] = _args.startLevel end
        end)
        if _args.level ~= nil then COOPOrg.applyTraits(_playerObj, _args.level) end
    end
end

if isServer() then
    Events.OnClientCommand.Add(onClientCommand)
end

COOPOrg.register()
Events.OnGameBoot.Add(COOPOrg.register)
Events.OnGameStart.Add(COOPOrg.register)
if Events.OnServerStarted then Events.OnServerStarted.Add(COOPOrg.register) end
