--
-- CO-OP - digging clay out of a riverbank.
--
-- With a shovel in your bags, right-clicking natural ground that has open water next to
-- it offers "Dig for clay". The dig is the vanilla garden-plot dig in everything the
-- player can see - the same animation, the same sound, the same metabolic cost - and it
-- hands over one to eleven lumps of Base.Clay depending on Pottery, plus 10 Pottery
-- XP. A square that has been dug gives nothing again for a week.
--
-- How this relates to the clay B42 already has. Vanilla has two clay sources and this is
-- a third, deliberately placed between them:
--
--   * foraging picks up 2-4 Base.Clay from the Stones category at any skill level;
--   * the four clay ground sprites (blends_natural_01_96/101/102/103, laid down by
--     worldgen only along lake shores and riverbanks) can be shovelled into a Claybag
--     with an empty sack, which unpacks into 8 Base.Clay. That is one-shot: the tile is
--     stamped `shovelled` in its mod data and swapped for plain dirt forever.
--
-- We do not touch either path. Ours needs no sack, works on any natural ground beside
-- water rather than only on the rare clay sprite, leaves the tile alone, and renews
-- itself on a timer instead of being used up - so the two digging paths do not compete
-- for the same squares, and a clay tile beside a river can still be taken as a Claybag
-- afterwards.
--
-- The shared state is the cooldown, and that is the server's: two players must not be
-- able to dig the same square twice in the same week. Same shape as the to-do list -
-- the server owns the table in GlobalModData, clients hold a cache so the menu can grey
-- itself out, and single player calls the authority directly.
--

require "COOP_Common"

COOPClay = COOPClay or {}

COOPClay.MODULE = "CO-OP"

-- commands on the mod channel
COOPClay.CMD_DIG = "clayDig"
COOPClay.CMD_SYNC_REQUEST = "clayRequestSync"
COOPClay.CMD_SYNC = "claySync"
COOPClay.CMD_DELTA = "clayDelta"
COOPClay.CMD_RESULT = "clayResult"

COOPClay.MODDATA_KEY = "COOP_Clay"
COOPClay.SCHEMA = 1

COOPClay.ITEM = "Base.Clay"

-- Pottery: B42 files clay under pottery and masonry, and every vanilla consumer of
-- Base.Clay is a Pottery or Masonry recipe. Perks.FromString is used rather than
-- Perks.Pottery so a missing name fails as nil instead of throwing.
COOPClay.PERK_NAME = "Pottery"

-- How far the open water may be from the square being dug, in tiles. 1 means the eight
-- squares around it, which is what "right on the bank" means.
COOPClay.WATER_REACH = 1

-- How far the player may stand from the square. Two tiles, not one: they walk adjacent
-- before digging, and the server checks this again with a tile of slack.
COOPClay.REACH = 2

-- Defaults for everything the sandbox options override. Read through the helpers below,
-- never cached - SandboxVars is empty until the world loads and arrives from the server
-- on a multiplayer client.
COOPClay.COOLDOWN_DAYS = 7
COOPClay.XP = 10
COOPClay.YIELD_RATE = 1.0

-- The dig itself. A garden furrow is 110 (ISPlowAction:getDuration) and taking a sack of
-- dirt is 100 (ISShovelGround); digging a hole for clay is the heavier job of the three.
COOPClay.DIG_TIME = 200

-- Cooldown entries we are willing to keep. Each one expires on its own, so the table is
-- bounded by how much digging a server does in one cooldown period; the cap is only
-- there so a pathological save cannot grow without limit.
COOPClay.MAX_ENTRIES = 2000

COOPClay.WRITE_WINDOW_MS = 2000
COOPClay.WRITE_LIMIT = 10

-- Set to true to trace every dig on both sides.
COOPClay.debug = false

function COOPClay.isEnabled()
    return COOP.featureEnabled(COOP.F_CLAY)
end

function COOPClay.cooldownDays()
    return COOP.numberOption("ClayCooldownDays", COOPClay.COOLDOWN_DAYS, 0, 60)
end

function COOPClay.digXp()
    return COOP.numberOption("ClayDigXp", COOPClay.XP, 0, 200)
end

function COOPClay.yieldRate()
    return COOP.numberOption("ClayYieldRate", COOPClay.YIELD_RATE, 0.1, 5.0)
end

-- ---------------------------------------------------------------------------
-- time
--
-- Everything is measured in in-game days off getWorldAgeHours(), the same clock vanilla's
-- own wormCheck uses for its seven-day window (ISPlowAction.lua). It is monotonic and it
-- survives a save, which neither the calendar date nor a real-time stamp manages.
-- ---------------------------------------------------------------------------

function COOPClay.nowDays()
    return COOP.worldAgeHours() / 24.0
end

-- ---------------------------------------------------------------------------
-- the square
-- ---------------------------------------------------------------------------

function COOPClay.squareKey(_x, _y, _z)
    return tostring(math.floor(_x)) .. "," .. tostring(math.floor(_y)) .. "," .. tostring(math.floor(_z))
end

-- Is this natural ground a shovel can be put into?
--
-- ISShovelGroundCursor.GetDirtGravelSand is vanilla's own answer and the one the clay
-- sack path already uses: it walks the square's non-item objects and classifies the first
-- floor sprite it recognises as "gravel", "sand", "clay" or "dirt", skipping anything
-- already stamped `shovelled`. Any of those four is ground we are happy to dig.
--
-- It lives in media/lua/server, which the game loads into the client state as well as the
-- server's (only client/ is skipped on a dedicated server), so both sides can ask. It is
-- still guarded: the fallback repeats the sprite test DiggingUtil.mining_floorCanDig
-- makes, which is the same prefixes one layer up.
function COOPClay.isDiggableGround(_square)
    if _square == nil then return false end

    if ISShovelGroundCursor ~= nil and ISShovelGroundCursor.GetDirtGravelSand ~= nil then
        local ok, kind = pcall(function()
            return ISShovelGroundCursor.GetDirtGravelSand(_square)
        end)
        if ok then return kind ~= nil end
    end

    -- fallback: the floor sprite, the way the mining code tests it
    local okFloor, natural = pcall(function()
        local floor = _square:getFloor()
        if floor == nil or floor:getSprite() == nil then return false end
        local name = floor:getSprite():getName()
        if name == nil then return false end
        return luautils.stringStarts(name, "floors_exterior_natural")
                or luautils.stringStarts(name, "blends_natural_01")
    end)
    return okFloor and natural == true
end

-- ---------------------------------------------------------------------------
-- water
--
-- "Next to open water" is a question B42 already asks, and the three tests below are
-- mirrors of the ones ISWorldObjectContextMenu uses to walk a player to a river before
-- filling a bottle (isValidWaterSquare / isValidShoreSquare / isSquareAdjacentToWater).
-- They are `local function`s in a client-only file, so they cannot be called - only
-- copied - but copying them means a bank the game considers a bank is a bank here too.
--
-- The test is the *floor tile's* water flag, not the square's aggregate properties that
-- the fishing code asks (`sq:getProperties():has(IsoFlagType.water)`). The floor is the
-- stricter question: a bathtub, a sink or a rain barrel standing on dry land is an
-- object with a fluid container, never a floor flagged as water, so none of them turn a
-- kitchen into a riverbank. Rain puddles are a weather effect painted over the floor and
-- carry no flag at all - vanilla's own ISTakeWaterAction identifies a puddle by the
-- *absence* of that flag.
--
-- The flag alone is not quite enough, though, and this is the trap worth recording. Of
-- the 425 vanilla tilesets only four tiles carry `water` at all - blends_natural_02_0,
-- _5, _6 and _7, the open surface. The twelve tiles around them, the shoreline blends
-- the water meets the bank through, carry `FloorMaterial = Water` and `taintedWater` but
-- *not* the flag. Testing the flag by itself would therefore mean "within one tile of
-- deep water", which on most banks is nowhere a shovel can reach: the blends sit in
-- between. IsoGridSquare.isWaterSquare() is the engine's own FloorMaterial test and
-- picks those blends up, so the pair of them is the whole water surface, edge included.
--
-- All of it is plain engine calls on IsoGridSquare and IsoObject, so the server can ask
-- the same question of its own copy of the map - which is what lets it check the story
-- a digging client tells it.
-- ---------------------------------------------------------------------------

function COOPClay.isWaterSquare(_square)
    if _square == nil then return false end

    local ok, wet = pcall(function()
        local floor = _square:getFloor()
        if floor ~= nil and floor:hasProperty(IsoFlagType.water) then return true end
        -- the shoreline blends: FloorMaterial = Water, no flag
        return _square:isWaterSquare() == true
    end)

    return ok and wet == true
end

-- A square you could stand on at the edge of the water: it has a floor, that floor is
-- not part of the water surface, and nothing solid is in the way.
function COOPClay.isShoreSquare(_square)
    if _square == nil then return false end

    local ok, shore = pcall(function()
        if _square:isSolid() or _square:isSolidTrans() then return false end
        if _square:getFloor() == nil then return false end
        return true
    end)
    if not ok or shore ~= true then return false end

    return not COOPClay.isWaterSquare(_square)
end

-- Open water within `_reach` tiles of a shore square. At the default reach of 1 this is
-- exactly vanilla's isSquareAdjacentToWater: the eight squares around this one, reached
-- through getAdjacentSquare so no cell lookup is needed and an unloaded neighbour simply
-- answers nil. A larger reach falls back to walking the box by hand.
function COOPClay.hasWaterNear(_square, _reach)
    if _square == nil then return false end
    if not COOPClay.isShoreSquare(_square) then return false end

    local reach = _reach or COOPClay.WATER_REACH

    if reach <= 1 then
        for i = 1, 8 do
            local ok, wet = pcall(function()
                return COOPClay.isWaterSquare(_square:getAdjacentSquare(IsoDirections.fromIndex(i - 1)))
            end)
            if ok and wet then return true end
        end
        return false
    end

    local cell = getCell()
    if cell == nil then return false end

    local x, y, z = _square:getX(), _square:getY(), _square:getZ()
    for dx = -reach, reach do
        for dy = -reach, reach do
            if dx ~= 0 or dy ~= 0 then
                local ok, wet = pcall(function()
                    return COOPClay.isWaterSquare(cell:getGridSquare(x + dx, y + dy, z))
                end)
                if ok and wet then return true end
            end
        end
    end

    return false
end

-- Everything the square itself has to be for a dig to be possible, in one place so the
-- menu and the server ask exactly the same question.
function COOPClay.canDigSquare(_square)
    if _square == nil then return false end
    if not COOPClay.isDiggableGround(_square) then return false end
    return COOPClay.hasWaterNear(_square, COOPClay.WATER_REACH)
end

-- ---------------------------------------------------------------------------
-- the shovel
--
-- Never a hardcoded item list. ItemTag.TAKE_DIRT is exactly the game's own notion of
-- "a shovel that can lift ground material into something": vanilla's clay-sack path uses
-- it (ISInventoryBuildMenu's predicateTakeDirt, ISShovelGroundCursor's predicateShovel),
-- and it is the narrower of the two dig tags - six items, the full-size shovels and
-- spades plus the entrenching tool and the hand shovel, where DIG_PLOW would also accept
-- a garden hoe and a mason's trowel. A mod's shovel carrying the tag is picked up free.
-- ---------------------------------------------------------------------------

local function predicateTakeDirt(_item)
    return not _item:isBroken() and _item:hasTag(ItemTag.TAKE_DIRT)
end

-- The shovel in the character's hand if there is one there, else the first in their bags -
-- the same order ISFarmingMenu.getShovel looks in, so the tool the player is already
-- holding is the one that gets used.
function COOPClay.findShovel(_character)
    if _character == nil then return nil end

    local ok, shovel = pcall(function()
        local hand = _character:getPrimaryHandItem()
        if hand ~= nil and predicateTakeDirt(hand) then return hand end
        return _character:getInventory():getFirstEvalRecurse(predicateTakeDirt)
    end)

    if ok then return shovel end
    return nil
end

-- ---------------------------------------------------------------------------
-- how much clay
-- ---------------------------------------------------------------------------

function COOPClay.perk()
    local ok, perk = pcall(function() return Perks.FromString(COOPClay.PERK_NAME) end)
    if ok and perk ~= nil then return perk end
    return nil
end

function COOPClay.perkLevel(_character)
    if _character == nil then return 0 end

    local perk = COOPClay.perk()
    if perk == nil then return 0 end

    local ok, level = pcall(function() return _character:getPerkLevel(perk) end)
    if ok and level ~= nil then return level end
    return 0
end

-- The design's ladder is 1 -> 1-3, 2 -> 2-3, 3 -> 3-4, "and so on up the scale". Read as
-- a closed form that is the level itself at the bottom and one more at the top:
--
--     low  = max(1, level)          never nothing, and never negative at level 0
--     high = max(3, level + 1)      the floor of three is what makes level 1 a 1-3
--
-- which gives 1-3 / 2-3 / 3-4 exactly as asked, walks up to 10-11 at the top of the
-- scale, and leaves level 0 at 1-3 as well - the floor on the maximum swallows the step
-- between 0 and 1, which is the honest consequence of the numbers the design gave rather
-- than a special case bolted on.
--
-- The sandbox multiplier scales both ends afterwards and can never take the yield below
-- one lump: a dig that found nothing would read as a bug.
function COOPClay.amountFor(_level)
    local level = tonumber(_level) or 0
    if level ~= level then level = 0 end
    level = math.max(0, math.min(10, math.floor(level)))

    local low = math.max(1, level)
    local high = math.max(3, level + 1)

    local rate = COOPClay.yieldRate()
    if rate ~= 1.0 then
        low = math.max(1, math.floor(low * rate + 0.5))
        high = math.max(low, math.floor(high * rate + 0.5))
    end

    return low, high
end

-- One dig's worth, rolled on the side that is actually spawning the clay.
function COOPClay.rollAmount(_level)
    local low, high = COOPClay.amountFor(_level)
    if high <= low then return low end
    return ZombRand(low, high + 1)
end

-- ---------------------------------------------------------------------------
-- the cooldown, as the client sees it
--
-- Both sides read the same shape of table: key -> the in-game day the square was last
-- dug. The server's is the authority in GlobalModData; the client's is a cache fed by
-- sync and delta, and is only ever used to grey a menu entry out early.
-- ---------------------------------------------------------------------------

-- Days left before this square gives clay again; 0 when it is ready now.
function COOPClay.cooldownLeft(_entries, _key)
    if _entries == nil or _key == nil then return 0 end

    local dug = tonumber(_entries[_key])
    if dug == nil then return 0 end

    local period = COOPClay.cooldownDays()
    if period <= 0 then return 0 end

    -- A dig stamped in the future means the clock moved backwards (a rolled-back save);
    -- treat it as ready rather than locking the square out for good.
    local elapsed = COOPClay.nowDays() - dug
    if elapsed < 0 then return 0 end
    if elapsed >= period then return 0 end

    return period - elapsed
end

-- "about 3 days" / "about 5 hours", for the greyed-out menu entry.
function COOPClay.waitText(_daysLeft)
    if _daysLeft == nil or _daysLeft <= 0 then return nil end

    if _daysLeft >= 1 then
        return getText("ContextMenu_COOP_Clay_WaitDays", tostring(math.ceil(_daysLeft)))
    end

    local hours = math.max(1, math.ceil(_daysLeft * 24))
    return getText("ContextMenu_COOP_Clay_WaitHours", tostring(hours))
end
