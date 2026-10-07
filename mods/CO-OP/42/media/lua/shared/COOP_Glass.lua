--
-- CO-OP - Glassmaking: car glass, a house window, and reglazing a smashed one.
--
-- Three things, sharing one sandbox switch:
--
--   * twelve craft recipes for car glass (scripts/craftrecipe_coop_glass.txt), one per
--     window part and vehicle class. Vanilla has the items and the mechanics to fit
--     them but no way at all to make one, so a car with its windshield gone stayed that
--     way until the loot turned one up;
--   * a craft recipe for a whole wooden house window, which comes out as the same
--     moveable vanilla hands you when you crowbar one off a wall, so it goes back in
--     with the vanilla Place cursor;
--   * "Reglaze window" on a smashed window, which vanilla cannot fix: its own glazed
--     window build (entity Wooden_Windows) refuses any frame that still holds an
--     IsoWindow, and a smashed window is still one.
--
-- The recipes are data and need nothing from this file except the two hooks they name,
-- OnTest and OnCreate. The reglaze is a timed action on the client and the work on the
-- server, same split as the clay dig.
--

require "COOP_Common"

COOPGlass = COOPGlass or {}

COOPGlass.MODULE = "CO-OP"

COOPGlass.CMD_REGLAZE = "glassReglaze"
COOPGlass.CMD_RESULT = "glassResult"

-- The moveable a crafted house window becomes: vanilla's plain wooden window, facing
-- west. Its sprite group carries the north-facing twin (_1), and the Place cursor
-- rotates between the two, so one sprite serves both walls.
COOPGlass.HOUSE_WINDOW_SPRITE = "fixtures_windows_01_0"

-- Reglazing: what it takes. Four panes is what vanilla's own glazed-window build uses
-- for the same opening.
COOPGlass.PANE = "Base.GlassPanel"
COOPGlass.PANES_PER_WINDOW = 4
COOPGlass.PERK_NAME = "Glassmaking"
COOPGlass.REGLAZE_LEVEL = 2
COOPGlass.REGLAZE_XP = 15
COOPGlass.REGLAZE_TIME = 200

-- How close the player must stand to the window, in tiles. The server allows one more
-- for a player who shuffled while the action finished.
COOPGlass.REACH = 2

-- Writes per player before the server starts refusing, and the window it counts them in.
COOPGlass.WRITE_LIMIT = 10
COOPGlass.WRITE_WINDOW_MS = 2000

COOPGlass.debug = false

function COOPGlass.isEnabled()
    return COOP.featureEnabled(COOP.F_GLASS)
end

-- ---------------------------------------------------------------------------
-- the recipe hooks
-- ---------------------------------------------------------------------------

-- OnTest on every recipe in craftrecipe_coop_glass.txt. The engine asks it of each
-- candidate input item (CraftRecipe.OnTestItem(item, character)), so answering false
-- for everything is what makes the recipe unmakeable while the feature is off - a script
-- recipe cannot be hidden from Lua, but it can be starved.
function COOPGlass.onTest(_item, _character)
    return COOPGlass.isEnabled()
end

-- Builds the moveable item for a sprite the way a pickup does, so its name, icon and
-- weight (PickUpWeight / 10, here 10 kg) come from the tile, not from us.
function COOPGlass.makeMoveable(_spriteName)
    local item = nil

    pcall(function()
        if ISMoveableSpriteProps ~= nil then
            local props = ISMoveableSpriteProps.new(getSprite(_spriteName))
            if props ~= nil and props.isMoveable then
                item = props:instanceItem(_spriteName)
            end
        end
    end)
    if item ~= nil then return item end

    -- The same thing by hand, in case the props object would not build.
    pcall(function()
        local moveable = instanceItem("Moveables." .. _spriteName)
        if moveable ~= nil and moveable:ReadFromWorldSprite(_spriteName) then
            item = moveable
        end
    end)
    return item
end

-- OnCreate on MakeCOOPHouseWindow: (craftRecipeData, character), called from inside
-- ISHandcraftAction:performRecipe on the side that performs the craft - the server in
-- multiplayer. Actions.addOrDropItem is the output picker's redirect for the length of
-- that call, so the window lands wherever the player's smithing output goes, and falls
-- back to vanilla's add-or-drop (which syncs it) otherwise.
function COOPGlass.onCreateHouseWindow(_craftRecipeData, _character)
    if _character == nil then return end

    local item = COOPGlass.makeMoveable(COOPGlass.HOUSE_WINDOW_SPRITE)
    if item == nil then
        COOP.log("glass: could not build a house window item from " .. COOPGlass.HOUSE_WINDOW_SPRITE)
        return
    end

    Actions.addOrDropItem(_character, item)

    if COOPGlass.debug then
        COOP.log("glass: " .. COOP.playerName(_character) .. " made a house window")
    end
end

-- ---------------------------------------------------------------------------
-- reglazing
-- ---------------------------------------------------------------------------

function COOPGlass.perk()
    local ok, perk = pcall(function() return Perks.FromString(COOPGlass.PERK_NAME) end)
    if ok then return perk end
    return nil
end

function COOPGlass.perkLevel(_character)
    if _character == nil then return 0 end
    local perk = COOPGlass.perk()
    if perk == nil then return 0 end
    local ok, level = pcall(function() return _character:getPerkLevel(perk) end)
    if ok and level ~= nil then return level end
    return 0
end

-- A window with no glass in it. In the engine "smashed" is the window's `destroyed`
-- field - isSmashed and isDestroyed read the same flag - and a window whose shards
-- were cleared out (Remove Broken Glass) is smashed *and* glassRemoved, so asking
-- isSmashed covers both.
function COOPGlass.needsGlass(_window)
    if _window == nil or not instanceof(_window, "IsoWindow") then return false end
    local ok, smashed = pcall(function() return _window:isSmashed() end)
    return ok and smashed == true
end

-- The panes the character carries, main inventory and bags alike.
function COOPGlass.countPanes(_character)
    if _character == nil then return 0 end
    local ok, count = pcall(function()
        return _character:getInventory():getCountTypeRecurse(COOPGlass.PANE)
    end)
    if ok and count ~= nil then return count end
    return 0
end

-- Why this character cannot reglaze this window, or nil when they can. Shared, so the
-- menu greys itself out for exactly the reasons the server will refuse.
function COOPGlass.reglazeProblem(_character, _window)
    if not COOPGlass.isEnabled() then return "off" end
    if not COOPGlass.needsGlass(_window) then return "whole" end
    local barricaded = false
    pcall(function() barricaded = _window:isBarricaded() end)
    if barricaded then return "barricaded" end
    if COOPGlass.perkLevel(_character) < COOPGlass.REGLAZE_LEVEL then return "skill" end
    if COOPGlass.countPanes(_character) < COOPGlass.PANES_PER_WINDOW then return "panes" end
    return nil
end

-- Finds the window on a square that matches a facing. Client and server both locate it
-- this way, because the IsoWindow itself is not something to send over the wire.
-- getWindow(direction) is the engine's own lookup, the one the moveables code places a
-- window by; the walk over every object is the fallback if that call ever misbehaves.
function COOPGlass.findWindow(_square, _north)
    if _square == nil then return nil end
    local north = _north == true

    local ok, window = pcall(function()
        return _square:getWindow(north and GridSquareEdgeFacingDirection.NORTH_SOUTH
                or GridSquareEdgeFacingDirection.EAST_WEST)
    end)
    if ok and window ~= nil then return window end

    local objects = _square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if instanceof(object, "IsoWindow") and object:getNorth() == north then
            return object
        end
    end
    return nil
end
