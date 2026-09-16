--
-- CO-OP - the concrete mixer.
--
-- Build 42 ships the object (the "Mortar Grinder" of construction_01, which the game's
-- own loot item calls Mov_ConcreteMixer) but nothing interacts with it. This gives it:
--
--   * a pick-up weight of 30 kg, through the vanilla moveables system
--   * a 30 litre fluid container that fills from the rain, like a barrel
--   * a 30 kg item container
--   * clay cement, mixed from what is inside it
--
-- Almost all of that is bought with four tile properties. B42 builds an object's item
-- container and its fluid container from its sprite when the chunk loads (CellLoader ->
-- IsoObject.createContainersFromSpriteProperties / .createFluidContainersFromSpriteProperties),
-- and the moveables system reads the pick-up weight from the same place. So the mod
-- writes the properties onto the four mixer sprites before any cell is loaded and the
-- engine does the rest - including the multiplayer sync of both containers, which is
-- the part that would be painful to do by hand.
--
-- Property names are the ones in zombie.core.properties.TilePropertyKey; they are the
-- same keys the .tiles files use.
--

require "COOP_Common"

COOPMixer = COOPMixer or {}

COOPMixer.MODULE = "CO-OP"
COOPMixer.CMD_CRAFT = "mixerCraft"
COOPMixer.CMD_SEEN = "mixerSeen"

-- Where the mixers somebody has used are, so the rain can find them again.
COOPMixer.MODDATA_KEY = "COOP_Mixers"
COOPMixer.MAX_SPOTS = 200

-- S, E, N, W. The game keeps one sprite per facing and they all want the same treatment.
COOPMixer.SPRITES = {
    "construction_01_6",
    "construction_01_7",
    "construction_01_14",
    "construction_01_15",
}

-- PickUpWeight is in tenths of a kilo (ISMoveableSpriteProps divides it by 10), so 300
-- is the 30 kg the design asks for. Vanilla ships it as 150.
COOPMixer.PICKUP_WEIGHT = 300

COOPMixer.FLUID_CAPACITY = 30      -- litres
COOPMixer.ITEM_CAPACITY = 30       -- kilos
COOPMixer.CONTAINER_TYPE = "crate" -- only picks the icon and the open/close sounds

-- Litres the open drum gathers in an hour of the heaviest rain. A vanilla rain barrel
-- is a much wider mouth on a much bigger vessel; this fills in a long wet day.
COOPMixer.RAIN_PER_HOUR = 4.0

-- How far the player may stand from the mixer and still work with it.
COOPMixer.REACH = 2

-- Set to true to trace what each mixer is carrying when it is opened. Remember that in
-- a hosted game the server's half of this lands in coop-console.txt, not console.txt.
COOPMixer.debug = false

function COOPMixer.isEnabled()
    return COOP.featureEnabled(COOP.F_MIXER)
end

-- ---------------------------------------------------------------------------
-- the sprites
-- ---------------------------------------------------------------------------

local propertiesApplied = false

-- Writes the tile properties the whole feature rests on. Idempotent, and deliberately
-- run from several events: it has to happen before the first chunk loads, and the
-- earliest event that has sprites is not the same one in every game mode.
function COOPMixer.applySpriteProperties()
    if propertiesApplied then return end
    if not COOPMixer.isEnabled() then return end

    local touched = 0

    for _, name in ipairs(COOPMixer.SPRITES) do
        local ok, err = pcall(function()
            local sprite = getSprite(name)
            if sprite == nil then return end

            local props = sprite:getProperties()
            if props == nil then return end

            -- 30 kg in the hands, instead of vanilla's 15
            props:set("PickUpWeight", tostring(COOPMixer.PICKUP_WEIGHT))

            -- A water collector cannot be picked up or scrapped while it holds fluid
            -- (ISMoveableSpriteProps:canPickUpMoveableInternal checks exactly this), so
            -- the "empty it first" rule comes from vanilla rather than from us.
            props:set("IsWaterCollector", "")

            -- the fluid container, in the same units the well and the rain barrels use
            props:set("waterAmount", "0")
            props:set("waterMaxAmount", tostring(COOPMixer.FLUID_CAPACITY))

            -- the item container
            props:set("container", COOPMixer.CONTAINER_TYPE)
            props:set("ContainerCapacity", tostring(COOPMixer.ITEM_CAPACITY))

            -- the property container keeps a key array alongside the map; without this
            -- the new keys are in the map but not in anything that walks the keys
            props:CreateKeySet()
            touched = touched + 1
        end)
        if not ok then
            COOP.log("concrete mixer: could not set up " .. name .. ": " .. tostring(err))
        end
    end

    if touched > 0 then
        propertiesApplied = true
        COOP.log("concrete mixer ready on " .. touched .. " sprites")
    end
end

function COOPMixer.isMixer(_object)
    if _object == nil then return false end

    local ok, name = pcall(function()
        local sprite = _object:getSprite()
        return sprite and sprite:getName() or nil
    end)
    if not ok or name == nil then return false end

    for _, sprite in ipairs(COOPMixer.SPRITES) do
        if sprite == name then return true end
    end
    return false
end

-- The mixer standing on a square, or nil.
function COOPMixer.findOnSquare(_square)
    if _square == nil then return nil end

    local objects = _square:getObjects()
    if objects == nil then return nil end

    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if COOPMixer.isMixer(object) then return object end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- the two containers
-- ---------------------------------------------------------------------------

-- Builds the two containers if this copy of the object has not got them.
--
-- This has to run on **both** sides, which is the opposite of the mod's usual rule and
-- worth being clear about. `createContainersFromSpriteProperties` is a local, purely
-- deterministic construction: at chunk load the server and every client each call it
-- themselves, off the same sprite properties, and the containers line up because they
-- are built in the same order from the same data. It is not shared state being invented
-- on a client - it is the same build the engine would have done, done late.
--
-- It is needed at all because an object restored from a chunk the save already holds
-- comes back as it was written, and a mixer that was walked past before this mod existed
-- was written without containers. A freshly generated chunk needs none of this.
--
-- Only the rain register, which really is shared state, stays server-side.
function COOPMixer.prepare(_object)
    if _object == nil then return end

    pcall(function()
        local built = false

        if _object:getContainerCount() == 0 then
            _object:createContainersFromSpriteProperties()
            built = _object:getContainerCount() > 0
        end
        if _object:getFluidCapacity() <= 0 then
            _object:createFluidContainersFromSpriteProperties()
            built = built or _object:getFluidCapacity() > 0
        end

        if built or COOPMixer.debug then
            COOP.log("concrete mixer: containers " .. tostring(_object:getContainerCount())
                    .. ", fluid capacity " .. tostring(_object:getFluidCapacity())
                    .. (built and " (built now)" or ""))
        end
    end)

    COOPMixer.remember(_object)
end

-- ---------------------------------------------------------------------------
-- rain
--
-- The engine only rains into a fluid container that was told to catch rain, and the
-- container of a plain IsoObject is not reachable from Lua - IsoObject exposes its
-- fluid (getFluidAmount, addFluid, transferFluidFrom, ...) but not the container
-- object itself, so there is nowhere to call setRainCatcher. The mod therefore does
-- the collecting: it notes where the mixers people have used are and tops them up
-- while it rains.
--
-- A mixer nobody has opened yet is not on the list, and one in an unloaded chunk is
-- skipped - the object is not in memory to pour into.
-- ---------------------------------------------------------------------------

local function spotKey(_x, _y, _z)
    return tostring(_x) .. "," .. tostring(_y) .. "," .. tostring(_z)
end

local function spotData()
    local data = ModData.getOrCreate(COOPMixer.MODDATA_KEY)
    if data.version == nil then data.version = 1 end
    if data.spots == nil then data.spots = {} end
    return data
end

function COOPMixer.remember(_object)
    if _object == nil or isClient() then return end

    local square = _object:getSquare()
    if square == nil then return end

    local data = spotData()
    local key = spotKey(square:getX(), square:getY(), square:getZ())
    if data.spots[key] ~= nil then return end

    local count = 0
    for _ in pairs(data.spots) do count = count + 1 end
    if count >= COOPMixer.MAX_SPOTS then return end

    data.spots[key] = { x = square:getX(), y = square:getY(), z = square:getZ() }
end

function COOPMixer.rainTick()
    if isClient() or not COOPMixer.isEnabled() then return end

    local intensity = 0
    pcall(function() intensity = getClimateManager():getPrecipitationIntensity() end)
    if intensity <= 0 then return end

    -- snow piles up on the lid rather than running into the drum
    local snow = false
    pcall(function() snow = getClimateManager():isSnow() end)
    if snow then return end

    local litres = COOPMixer.RAIN_PER_HOUR * intensity / 6.0  -- this event is ten minutes
    if litres <= 0 then return end

    local data = spotData()
    local stale = {}

    for key, spot in pairs(data.spots) do
        local square = getCell() and getCell():getGridSquare(spot.x, spot.y, spot.z) or nil
        if square ~= nil then
            local mixer = COOPMixer.findOnSquare(square)
            if mixer == nil then
                -- picked up, scrapped or never there: stop looking for it
                table.insert(stale, key)
            elseif square:isOutside() then
                pcall(function()
                    local room = mixer:getFluidCapacity() - mixer:getFluidAmount()
                    if room <= 0 then return end
                    mixer:addFluid(FluidType.Water, math.min(litres, room))
                    mixer:sync()
                end)
            end
        end
    end

    for _, key in ipairs(stale) do data.spots[key] = nil end
end

function COOPMixer.getContainer(_object)
    if _object == nil then return nil end
    local ok, container = pcall(function()
        return _object:getContainerByType(COOPMixer.CONTAINER_TYPE) or _object:getContainer()
    end)
    if ok then return container end
    return nil
end

-- Litres in the drum and litres it holds. 0, 0 when the container never got built.
function COOPMixer.getWater(_object)
    if _object == nil then return 0, 0 end
    local ok, amount, capacity = pcall(function()
        return _object:getFluidAmount(), _object:getFluidCapacity()
    end)
    if ok and amount ~= nil and capacity ~= nil then return amount, capacity end
    return 0, 0
end

-- Kilos inside and kilos it holds.
function COOPMixer.getLoad(_object)
    local container = COOPMixer.getContainer(_object)
    if container == nil then return 0, 0 end

    local ok, used, capacity = pcall(function()
        return container:getCapacityWeight(), container:getMaxWeight()
    end)
    if ok and used ~= nil and capacity ~= nil then return used, capacity end
    return 0, COOPMixer.ITEM_CAPACITY
end

-- ---------------------------------------------------------------------------
-- what it can mix
-- ---------------------------------------------------------------------------

-- The vanilla recipes (MakeBucketOfClayCement / ...FromGrass) with the water coming out
-- of the mixer instead of out of the bucket. Same inputs, same outputs, same item - so
-- what comes out is ordinary clay cement that every vanilla recipe already accepts.
COOPMixer.RECIPES = {
    {
        id = "cement",
        label = "UI_COOP_Mixer_Recipe_Cement",
        time = 150,
        water = 10.0,
        inputs = {
            {
                label = "UI_COOP_Mixer_Input_Bucket",
                types = { "Base.Bucket", "Base.BucketEmpty", "Base.BucketCarved" },
                count = 1,
                -- the bucket becomes the cement, so which one went in decides what comes out
                mapsOutput = true,
            },
            { label = "UI_COOP_Mixer_Input_Clay", types = { "Base.Clay" }, count = 2 },
            { label = "UI_COOP_Mixer_Input_Sand", types = { "Base.Sandbag" }, count = 1 },
        },
        output = "Base.BucketClayCement",
        outputMap = { ["Base.BucketCarved"] = "Base.BucketCarvedClayCement" },
    },
    {
        id = "cementGrass",
        label = "UI_COOP_Mixer_Recipe_CementGrass",
        time = 150,
        water = 10.0,
        inputs = {
            {
                label = "UI_COOP_Mixer_Input_Bucket",
                types = { "Base.Bucket", "Base.BucketEmpty", "Base.BucketCarved" },
                count = 1,
                mapsOutput = true,
            },
            { label = "UI_COOP_Mixer_Input_Clay", types = { "Base.Clay" }, count = 2 },
            {
                label = "UI_COOP_Mixer_Input_Grass",
                types = { "Base.GrassTuft", "Base.HayTuft" },
                count = 50,
            },
        },
        output = "Base.BucketClayCement",
        outputMap = { ["Base.BucketCarved"] = "Base.BucketCarvedClayCement" },
    },
}

function COOPMixer.recipeById(_id)
    for _, recipe in ipairs(COOPMixer.RECIPES) do
        if recipe.id == _id then return recipe end
    end
    return nil
end

-- Every item in the mixer matching one of these types, at most _count of them.
local function gather(_container, _types, _count)
    local found = {}
    if _container == nil then return found end

    local items = _container:getItems()
    if items == nil then return found end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item ~= nil then
            local fullType = item:getFullType()
            for _, wanted in ipairs(_types) do
                if fullType == wanted then
                    table.insert(found, item)
                    break
                end
            end
        end
        if #found >= _count then break end
    end

    return found
end

-- Can this be mixed right now? Returns true, or false plus the list of what is missing
-- (each entry a translation key and how many more are needed) so the UI can say why.
function COOPMixer.check(_object, _recipe)
    local missing = {}

    if _object == nil or _recipe == nil then return false, missing end

    local container = COOPMixer.getContainer(_object)
    local water = COOPMixer.getWater(_object)

    if water < _recipe.water then
        table.insert(missing, {
            label = "UI_COOP_Mixer_Input_Water",
            need = string.format("%.1f", _recipe.water - water),
        })
    end

    for _, input in ipairs(_recipe.inputs) do
        local found = gather(container, input.types, input.count)
        if #found < input.count then
            table.insert(missing, { label = input.label, need = tostring(input.count - #found) })
        end
    end

    return #missing == 0, missing
end

-- Consumes the inputs and puts the result in the mixer. Only ever called where the
-- object is authoritative: the server in multiplayer, the player in single player.
function COOPMixer.craft(_object, _recipe)
    if _object == nil or _recipe == nil then return false end
    if not COOPMixer.isEnabled() then return false end

    COOPMixer.prepare(_object)

    local ok, missing = COOPMixer.check(_object, _recipe)
    if not ok then return false end

    local container = COOPMixer.getContainer(_object)
    if container == nil then return false end

    local outputType = _recipe.output

    for _, input in ipairs(_recipe.inputs) do
        local found = gather(container, input.types, input.count)
        for _, item in ipairs(found) do
            if input.mapsOutput then
                local mapped = _recipe.outputMap and _recipe.outputMap[item:getFullType()]
                if mapped ~= nil then outputType = mapped end
            end
            container:Remove(item)
            sendRemoveItemFromContainer(container, item)
        end
    end

    pcall(function() _object:useFluid(_recipe.water) end)

    local product = instanceItem(outputType)
    if product == nil then
        COOP.log("concrete mixer: cannot create " .. tostring(outputType))
        return false
    end

    container:AddItem(product)
    sendAddItemToContainer(container, product)

    return true
end

-- ---------------------------------------------------------------------------

COOPMixer.applySpriteProperties()
Events.OnGameBoot.Add(COOPMixer.applySpriteProperties)
Events.EveryTenMinutes.Add(COOPMixer.rainTick)
Events.OnGameStart.Add(COOPMixer.applySpriteProperties)
if Events.OnLoadedTileDefinitions then
    Events.OnLoadedTileDefinitions.Add(COOPMixer.applySpriteProperties)
end
if Events.OnServerStarted then
    Events.OnServerStarted.Add(COOPMixer.applySpriteProperties)
end
