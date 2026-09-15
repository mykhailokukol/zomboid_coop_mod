--
-- CO-OP - where new items go.
--
-- Where items the player just produced end up: their hands, a worn bag, a container
-- next to them, or the ground. It covers
--   * crafting          (ISHandcraftAction:performRecipe)
--   * vehicle parts     (ISUninstallVehiclePart, ISTakeEngineParts)
--
-- The destination is chosen per kind of work - cooking, carpentry, car mechanics and
-- smithing each have their own, and everything else follows the default one. The client
-- resolves all of them and sends the whole set; the side that performs the action works
-- out which kind of work it is and picks the matching entry.
--
-- Both of those run on the server in multiplayer, so the placement lives in shared/
-- and the client only stamps the chosen destination onto the action.
--
-- Everything degrades to vanilla: if the destination is full, out of reach, refuses
-- the item, or cannot be resolved, the item stays where vanilla put it. A produced
-- item is never lost.
--

require "COOP_Common"

-- Deliberately no require of the vanilla action files. Requiring one makes the game
-- load it early, and it is then loaded a second time by the normal file scan, which
-- re-runs `Class = ISBaseTimedAction:derive(...)` and throws our hooks away. We wait
-- for the classes to exist instead, and re-check that our hooks are still in place.

COOPOutput = COOPOutput or {}

COOPOutput.HANDS = "hands"
COOPOutput.BAG = "bag"
COOPOutput.NEARBY = "nearby"
COOPOutput.GROUND = "ground"

-- Where the work is sorted into. "default" catches everything the rules below miss, and
-- is also what a category set to COOPOutput.GLOBAL falls back to.
COOPOutput.DEFAULT_CATEGORY = "default"
COOPOutput.COOKING = "cooking"
COOPOutput.CARPENTRY = "carpentry"
COOPOutput.MECHANICS = "mechanics"
COOPOutput.SMITHING = "smithing"
COOPOutput.CATEGORIES = {
    COOPOutput.COOKING, COOPOutput.CARPENTRY, COOPOutput.MECHANICS, COOPOutput.SMITHING,
}

-- A category may be left following the default one instead of naming a destination.
COOPOutput.GLOBAL = "global"

-- How far the target container may be from the player when the server resolves it.
COOPOutput.MAX_DISTANCE = 3

-- Set to true to trace every placement in console.txt / coop-console.txt.
COOPOutput.debug = false

-- Destinations the clients told us about, by username: one table of
-- category -> destination per player. Custom fields set on a timed action do NOT survive
-- the trip to the server (only the named parameters of the class's `new` are sent), so in
-- multiplayer the client pushes the whole set over the command channel and the server
-- reads it from here. Sending every category at once rather than only the one for the
-- action being created matters: a player can queue a carpentry craft and a cooking craft
-- before either of them runs, and the server must still place each output correctly.
COOPOutput.destinations = {}

COOPOutput.MODULE = "CO-OP"
COOPOutput.COMMAND = "output"

function COOPOutput.isModeValid(_mode)
    return _mode == COOPOutput.HANDS or _mode == COOPOutput.BAG
            or _mode == COOPOutput.NEARBY or _mode == COOPOutput.GROUND
end

local function isRedirecting(_destination)
    -- the single gate for the whole feature: with it off nothing is ever redirected and
    -- every production site keeps whatever vanilla did
    if not COOP.featureEnabled(COOP.F_OUTPUT) then return false end

    local mode = _destination and _destination.coopOutputMode or nil
    return COOPOutput.isModeValid(mode) and mode ~= COOPOutput.HANDS
end

-- ---------------------------------------------------------------------------
-- what kind of work a recipe is
-- ---------------------------------------------------------------------------

-- A recipe's `category` is the group it is filed under in the crafting window, which is
-- about presentation and does not always match the craft: all 89 vanilla Cooking recipes
-- declare no skill at all, while eighteen filed under "Tools" need Blacksmith 4. So both
-- are consulted. `involvesSkill` is the engine's own answer to "is this recipe about that
-- skill" - it checks the required skills, the XP awards and the autolearn lists - and
-- vanilla's CraftRecipe.isSmithing() is exactly this pair of tests, category first.
local CATEGORY_RULES = {
    {
        name = COOPOutput.COOKING,
        categories = { Cooking = true },
        perks = { "Cooking" },
    },
    {
        name = COOPOutput.CARPENTRY,
        categories = { Carpentry = true, Furniture = true },
        perks = { "Woodwork" },
    },
    {
        name = COOPOutput.MECHANICS,
        categories = { Vehicle = true, Mechanics = true },
        perks = { "Mechanics" },
    },
    {
        -- the forge/kiln bucket: blacksmithing, pottery and glassmaking, plus the
        -- neighbouring hot-and-hard-material work that would otherwise scatter
        name = COOPOutput.SMITHING,
        categories = {
            Blacksmithing = true, Pottery = true, Glassmaking = true,
            Metalworking = true, Welding = true, Masonry = true, Knapping = true,
        },
        perks = {
            "Blacksmith", "Pottery", "Glassmaking",
            "MetalWelding", "Masonry", "FlintKnapping",
        },
    },
}

local perkCache = {}

local function perkNamed(_name)
    if perkCache[_name] == nil then
        local ok, perk = pcall(function() return Perks.FromString(_name) end)
        perkCache[_name] = (ok and perk) or false
    end
    if perkCache[_name] == false then return nil end
    return perkCache[_name]
end

function COOPOutput.categoryForRecipe(_recipe)
    if _recipe == nil then return COOPOutput.DEFAULT_CATEGORY end

    local named = nil
    pcall(function() named = _recipe:getCategory() end)
    if named ~= nil then
        for _, rule in ipairs(CATEGORY_RULES) do
            if rule.categories[named] then return rule.name end
        end
    end

    for _, rule in ipairs(CATEGORY_RULES) do
        for _, perkName in ipairs(rule.perks) do
            local perk = perkNamed(perkName)
            if perk ~= nil then
                local ok, involved = pcall(function() return _recipe:involvesSkill(perk) end)
                if ok and involved == true then return rule.name end
            end
        end
    end

    return COOPOutput.DEFAULT_CATEGORY
end

-- Where this character's new items should go for that kind of work: the action carries
-- the whole set in single player, the client sends it ahead in multiplayer. A category
-- with nothing of its own falls back to the default one.
function COOPOutput.resolveDestination(_action, _character, _category)
    local category = _category or COOPOutput.DEFAULT_CATEGORY

    local function pick(_set)
        if _set == nil then return nil end
        return _set[category] or _set[COOPOutput.DEFAULT_CATEGORY]
    end

    -- single player is one Lua state, so the table the client stamped is right here
    local stamped = pick(_action ~= nil and _action.coopOutputDestinations or nil)
    if stamped ~= nil then return stamped end

    if _character == nil then return nil end

    local ok, username = pcall(function() return _character:getUsername() end)
    if ok and username ~= nil then
        return pick(COOPOutput.destinations[tostring(username)])
    end
    return nil
end

-- The worn container with the most room left that will take this item.
local function bestWornContainer(_character, _item)
    local best = nil
    local bestFree = -1

    local worn = _character:getWornItems()
    if worn == nil then return nil end

    for i = 0, worn:size() - 1 do
        local item = worn:getItemByIndex(i)
        if item ~= nil and instanceof(item, "InventoryContainer") then
            local container = item:getInventory()
            if container ~= nil and container:isItemAllowed(_item)
                    and container:hasRoomFor(_character, _item) then
                local free = container:getEffectiveCapacity(_character) - container:getCapacityWeight()
                if free > bestFree then
                    best = container
                    bestFree = free
                end
            end
        end
    end

    return best
end

-- Resolves the container the player picked. The indices are a fast path; the type is
-- the fallback, because the object order on a square need not match on both peers.
local function nearbyContainer(_destination, _character, _item)
    local x = _destination.coopOutputX
    local y = _destination.coopOutputY
    local z = _destination.coopOutputZ
    if x == nil or y == nil or z == nil then return nil end

    if math.abs(_character:getX() - x) > COOPOutput.MAX_DISTANCE
            or math.abs(_character:getY() - y) > COOPOutput.MAX_DISTANCE then
        COOP.log("the chosen container is too far away, keeping the item")
        return nil
    end

    local square = getCell():getGridSquare(x, y, z)
    if square == nil then return nil end

    local objects = square:getObjects()
    if objects == nil then return nil end

    local wantedType = _destination.coopOutputType

    local function usable(_container)
        return _container ~= nil
                and _container:isItemAllowed(_item)
                and _container:hasRoomFor(_character, _item)
    end

    local objectIndex = _destination.coopOutputObjectIndex
    local containerIndex = _destination.coopOutputContainerIndex
    if objectIndex ~= nil and containerIndex ~= nil and objectIndex < objects:size() then
        local object = objects:get(objectIndex)
        if object ~= nil then
            local container = object:getContainerByIndex(containerIndex)
            if usable(container) and (wantedType == nil or container:getType() == wantedType) then
                return container
            end
        end
    end

    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if object ~= nil then
            for j = 0, object:getContainerCount() - 1 do
                local container = object:getContainerByIndex(j)
                if usable(container) and (wantedType == nil or container:getType() == wantedType) then
                    return container
                end
            end
        end
    end

    return nil
end

-- Places a brand new item (not in any container yet). True when it was placed.
function COOPOutput.placeItem(_destination, _character, _item)
    if not isRedirecting(_destination) then return false end
    if COOPOutput.debug then
        COOP.log("placing " .. tostring(_item and _item:getFullType())
                .. " -> " .. tostring(_destination.coopOutputMode))
    end
    if _character == nil or _item == nil then return false end

    local mode = _destination.coopOutputMode

    if mode == COOPOutput.GROUND then
        local square = _character:getCurrentSquare()
        if square == nil then return false end
        square:AddWorldInventoryItem(_item, ZombRandFloat(0.1, 0.9), ZombRandFloat(0.1, 0.9), 0.0)
        return true
    end

    local container = nil
    if mode == COOPOutput.BAG then
        container = bestWornContainer(_character, _item)
    elseif mode == COOPOutput.NEARBY then
        container = nearbyContainer(_destination, _character, _item)
    end

    if container == nil then return false end

    container:AddItem(_item)
    -- same sync call vanilla's Actions.addOrDropItem makes, so clients see the item
    sendAddItemToContainer(container, _item)
    return true
end

-- Moves an item vanilla has just put in the player's inventory. True when it moved.
function COOPOutput.relocateFromInventory(_destination, _character, _item)
    if not isRedirecting(_destination) then return false end
    if _character == nil or _item == nil then return false end

    local inventory = _character:getInventory()
    if _item:getContainer() ~= inventory then return false end

    inventory:Remove(_item)
    if COOPOutput.placeItem(_destination, _character, _item) then return true end

    -- destination refused it: hand it back, vanilla's own sync call follows
    inventory:AddItem(_item)
    return false
end

-- ---------------------------------------------------------------------------
-- hooks
-- ---------------------------------------------------------------------------

-- Our own installed functions, so we can tell whether they are still in place.
local installed = {}

-- Actions that hand the item over by adding it to the player's inventory and then
-- syncing it. We intercept the sync call, move the item, and swallow the sync - our
-- own placement does the syncing instead.
local function withInventoryRedirect(_destination, _character, _perform)
    if not isRedirecting(_destination) or _character == nil then return _perform() end

    local originalSendOne = sendAddItemToContainer
    local originalSendMany = sendAddItemsToContainer
    local inventory = _character:getInventory()

    sendAddItemToContainer = function(_container, _item)
        if _container == inventory and COOPOutput.relocateFromInventory(_destination, _character, _item) then
            return
        end
        return originalSendOne(_container, _item)
    end

    sendAddItemsToContainer = function(_container, _items)
        if _container ~= inventory or _items == nil then
            return originalSendMany(_container, _items)
        end
        local left = ArrayList.new()
        for i = 0, _items:size() - 1 do
            local item = _items:get(i)
            if not COOPOutput.relocateFromInventory(_destination, _character, item) then
                left:add(item)
            end
        end
        if left:isEmpty() then return end
        return originalSendMany(_container, left)
    end

    local ok, result = pcall(_perform)

    sendAddItemToContainer = originalSendOne
    sendAddItemsToContainer = originalSendMany

    if not ok then
        COOP.log("output redirect failed: " .. tostring(result))
        return nil
    end
    return result
end

-- Wraps a class method, unless our wrapper is already the one in place.
--
-- This is re-checked on several events on purpose: the game loads its own Lua files
-- after a mod `require`s them, which re-runs `Class = ISBaseTimedAction:derive(...)`
-- and throws away anything a mod attached to the old class table. Patching once at
-- file load silently stopped working for exactly that reason.
local function hook(_class, _name, _key, _make)
    if _class == nil then return end
    if installed[_key] ~= nil and _class[_name] == installed[_key] then return end

    local original = _class[_name]
    if original == nil then return end

    local wrapper = _make(original)
    _class[_name] = wrapper
    installed[_key] = wrapper
    return true
end

local function install()
    local any = false

    -- ---- crafting ---------------------------------------------------------
    -- Vanilla hands each output to Actions.addOrDropItem; we swap that function for
    -- the duration of the call so all the bookkeeping around it stays vanilla.
    any = hook(ISHandcraftAction, "performRecipe", "performRecipe", function(_original)
        return function(self)
            local category = COOPOutput.categoryForRecipe(self.craftRecipe)
            local destination = COOPOutput.resolveDestination(self, self.character, category)
            if not isRedirecting(destination) then return _original(self) end

            local originalAddOrDropItem = Actions.addOrDropItem

            Actions.addOrDropItem = function(_character, _item)
                local ok, placed = pcall(COOPOutput.placeItem, destination, _character, _item)
                if ok and placed then return end
                if not ok then COOP.log("craft output failed, keeping vanilla: " .. tostring(placed)) end
                return originalAddOrDropItem(_character, _item)
            end

            local ok, err = pcall(_original, self)

            Actions.addOrDropItem = originalAddOrDropItem

            if not ok then COOP.log("craft failed: " .. tostring(err)) end
        end
    end) or any

    -- ---- vehicle parts ----------------------------------------------------
    -- Only where the item placement is authoritative; multiplayer clients get the
    -- result synced back from the server.
    any = hook(ISUninstallVehiclePart, "complete", "uninstallPart", function(_original)
        return function(self)
            if isClient() then return _original(self) end
            local destination = COOPOutput.resolveDestination(self, self.character, COOPOutput.MECHANICS)
            return withInventoryRedirect(destination, self.character, function()
                return _original(self)
            end)
        end
    end) or any

    any = hook(ISTakeEngineParts, "complete", "takeEngineParts", function(_original)
        return function(self)
            if isClient() then return _original(self) end
            local destination = COOPOutput.resolveDestination(self, self.character, COOPOutput.MECHANICS)
            return withInventoryRedirect(destination, self.character, function()
                return _original(self)
            end)
        end
    end) or any

    if any then COOP.log("item output redirect installed") end
end

-- The client sends its destination whenever it changes and again before each action.
local function onClientCommand(_module, _command, _playerObj, _args)
    if _module ~= COOPOutput.MODULE or _command ~= COOPOutput.COMMAND then return end
    if _playerObj == nil or _args == nil then return end

    local ok, username = pcall(function() return _playerObj:getUsername() end)
    if not ok or username == nil then return end

    COOPOutput.destinations[tostring(username)] = _args
    if COOPOutput.debug then
        local parts = {}
        for category, destination in pairs(_args) do
            table.insert(parts, tostring(category) .. "=" .. tostring(destination.coopOutputMode))
        end
        COOP.log("destinations from " .. tostring(username) .. ": " .. table.concat(parts, " "))
    end
end

if isServer() then
    Events.OnClientCommand.Add(onClientCommand)
end

COOPOutput.install = install

install()
Events.OnGameBoot.Add(install)
Events.OnGameStart.Add(install)
Events.OnInitGlobalModData.Add(install)
if Events.OnServerStarted then Events.OnServerStarted.Add(install) end
