--
-- CO-OP - "Reglaze window": the menu entry and the action.
--
-- The action is the visible half and does none of the work: it walks to the window,
-- plays the job and then tells the server which window it was. The panes, the window
-- and the XP are the server's, for the reasons in COOP_GlassServer.lua.
--
-- The recipes in craftrecipe_coop_glass.txt need nothing from this file.
--

if isServer() then return end

require "COOP_Glass"
require "TimedActions/ISBaseTimedAction"

COOPGlassUI = COOPGlassUI or {}

-- What came of it, in the glazier's own chat window. Only failures the player could
-- not have seen coming are worth a line; success is the window itself.
function COOPGlassUI.report(_ok, _reason)
    if _ok then return end
    if _reason == "panes" then
        COOP.sayInChat(getText("ContextMenu_COOP_Glass_NoPanes", tostring(COOPGlass.PANES_PER_WINDOW)))
    elseif _reason == "whole" then
        COOP.sayInChat(getText("UI_COOP_Glass_AlreadyWhole"))
    elseif _reason == "skill" then
        COOP.sayInChat(getText("ContextMenu_COOP_Glass_NoSkill", tostring(COOPGlass.REGLAZE_LEVEL)))
    elseif _reason == "barricaded" then
        COOP.sayInChat(getText("ContextMenu_COOP_Glass_Barricaded"))
    end
end

local function onServerCommand(_module, _command, _args)
    if _module ~= COOPGlass.MODULE then return end
    if _command ~= COOPGlass.CMD_RESULT then return end
    COOPGlassUI.report(_args and _args.ok == true, _args and _args.reason or nil)
end

Events.OnServerCommand.Add(onServerCommand)

-- ---------------------------------------------------------------------------
-- the action
--
-- Shaped on ISRemoveBrokenGlass, the vanilla action on the same object: face the window,
-- the Loot animation at mid height, light work. It deliberately has **no `complete`** -
-- a class that defines one is rebuilt on the server and run there as well, which would
-- take the panes twice. The work is in `perform` and goes over the command channel, as
-- the clay dig does.
-- ---------------------------------------------------------------------------

COOPReglazeAction = ISBaseTimedAction:derive("COOPReglazeAction")

function COOPReglazeAction:isValid()
    if self.window == nil or self.window:getObjectIndex() == -1 then return false end
    return COOPGlass.reglazeProblem(self.character, self.window) == nil
end

function COOPReglazeAction:waitToStart()
    self.character:faceThisObject(self.window)
    return self.character:shouldBeTurning()
end

function COOPReglazeAction:update()
    self.character:faceThisObject(self.window)
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function COOPReglazeAction:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Mid")
    self:setOverrideHandModels(nil, nil)
    self.sound = self.character:playSound("RemoveBrokenGlass")
end

function COOPReglazeAction:stop()
    if self.sound and self.sound ~= 0 then
        self.character:getEmitter():stopOrTriggerSound(self.sound)
    end
    ISBaseTimedAction.stop(self)
end

function COOPReglazeAction:perform()
    if self.sound and self.sound ~= 0 then
        self.character:getEmitter():stopOrTriggerSound(self.sound)
    end

    local square = self.window:getSquare()
    if square ~= nil then
        local args = {
            x = square:getX(),
            y = square:getY(),
            z = square:getZ(),
            north = self.window:getNorth() == true,
        }
        if isClient() then
            sendClientCommand(self.character, COOPGlass.MODULE, COOPGlass.CMD_REGLAZE, args)
        elseif COOPGlassServer ~= nil then
            -- single player: one Lua state, call the authority directly
            COOPGlassUI.report(COOPGlassServer.reglaze(self.character, args))
        end
    end

    ISBaseTimedAction.perform(self)
end

function COOPReglazeAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return COOPGlass.REGLAZE_TIME
end

function COOPReglazeAction:new(character, window)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.window = window
    o.maxTime = o:getDuration()
    o.caloriesModifier = 4
    return o
end

-- ---------------------------------------------------------------------------
-- the world context menu
-- ---------------------------------------------------------------------------

local function disable(_option, _reason)
    if _option == nil then return end
    _option.notAvailable = true
    if _reason ~= nil and ISWorldObjectContextMenu and ISWorldObjectContextMenu.addToolTip then
        local tooltip = ISWorldObjectContextMenu.addToolTip()
        tooltip.description = _reason
        _option.toolTip = tooltip
    end
end

local function onReglaze(_player, _window)
    -- the vanilla walk for anything on a window or door edge: it picks the side of the
    -- wall the player is already on
    if not luautils.walkAdjWindowOrDoor(_player, _window:getSquare(), _window) then return end
    ISTimedActionQueue.add(COOPReglazeAction:new(_player, _window))
end

-- The smashed window the click was about. The picker answers with whatever object was
-- on top - often the wall, not the window - so the clicked squares are searched for a
-- window too, both facings.
local function findSmashedWindow(_worldobjects)
    local seen = {}
    for _, object in ipairs(_worldobjects) do
        if instanceof(object, "IsoWindow") and COOPGlass.needsGlass(object) then
            return object
        end
        local square = object:getSquare()
        if square ~= nil and not seen[square] then
            seen[square] = true
            for _, north in ipairs({ true, false }) do
                local window = COOPGlass.findWindow(square, north)
                if COOPGlass.needsGlass(window) then return window end
            end
        end
    end
    return nil
end

local REASON_TEXT = {
    barricaded = function() return getText("ContextMenu_COOP_Glass_Barricaded") end,
    skill = function() return getText("ContextMenu_COOP_Glass_NoSkill", tostring(COOPGlass.REGLAZE_LEVEL)) end,
    panes = function() return getText("ContextMenu_COOP_Glass_NoPanes", tostring(COOPGlass.PANES_PER_WINDOW)) end,
}

local function onFillWorldObjectContextMenu(_playerNum, _context, _worldobjects, _test)
    if _test and ISWorldObjectContextMenu.Test then return true end
    if not COOPGlass.isEnabled() then return end

    local player = getSpecificPlayer(_playerNum)
    if player == nil or player:getVehicle() ~= nil then return end

    local window = findSmashedWindow(_worldobjects)
    if window == nil then return end

    if _test then return ISWorldObjectContextMenu.setTest() end

    local option = _context:addOption(getText("ContextMenu_COOP_Glass_Reglaze"), player, onReglaze, window)
    pcall(function() option.iconTexture = getTexture("Item_GlassPane") end)

    local problem = COOPGlass.reglazeProblem(player, window)
    if problem ~= nil then
        local text = REASON_TEXT[problem]
        disable(option, text and text() or nil)
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
