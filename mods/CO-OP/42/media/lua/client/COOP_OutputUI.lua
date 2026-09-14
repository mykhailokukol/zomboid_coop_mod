--
-- CO-OP - the "where do new items go" picker.
--
-- One global setting, saved next to the game's other .ini files, so it holds for every
-- character and every server on this machine. The same drop-down appears in the
-- crafting window and in the vehicle mechanics window; changing it in one changes it
-- everywhere, right away.
--

if isServer() then return end

require "COOP_Common"
require "COOP_Output"

local OPTIONS_FILE = "coop_options.ini"
local OPTION_KEY = "outputMode"

local UI_BORDER_SPACING = 10
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BUTTON_HGT = FONT_HGT_SMALL + 6
local NEARBY_RADIUS = 2

local mode = nil
local combos = {}

-- ---------------------------------------------------------------------------
-- the setting
-- ---------------------------------------------------------------------------

local function load()
    mode = COOPOutput.HANDS
    local ok = pcall(function()
        local reader = getFileReader(OPTIONS_FILE, false)
        if reader == nil then return end
        while true do
            local line = reader:readLine()
            if line == nil then break end
            local key, value = string.match(string.trim(line), "^([%w_]+)%s*=%s*(%S+)$")
            if key == OPTION_KEY and COOPOutput.isModeValid(value) then
                mode = value
            end
        end
        reader:close()
    end)
    if not ok then mode = COOPOutput.HANDS end
end

local function save()
    pcall(function()
        local writer = getFileWriter(OPTIONS_FILE, true, false)
        if writer == nil then return end
        writer:write(OPTION_KEY .. "=" .. tostring(mode) .. "\r\n")
        writer:close()
    end)
end

function COOPOutput.getMode()
    if mode == nil then load() end
    return mode
end

function COOPOutput.setMode(_mode)
    if not COOPOutput.isModeValid(_mode) then return end
    if mode == _mode then return end
    mode = _mode
    save()
    COOP.log("new items now go to: " .. _mode)
    COOPOutput.sendDestination()

    -- keep every open picker in step, and forget the ones whose window is gone
    local alive = {}
    for _, combo in ipairs(combos) do
        if combo ~= nil and combo.parent ~= nil then
            combo:selectData(_mode)
            table.insert(alive, combo)
        end
    end
    combos = alive
end

-- ---------------------------------------------------------------------------
-- picking the nearby container
-- ---------------------------------------------------------------------------

local function isWorldContainer(_container)
    return _container ~= nil and _container:getParent() ~= nil
end

-- The container the player has open wins; otherwise the closest one nearby.
function COOPOutput.findNearbyContainer(_character)
    if _character == nil then return nil end

    local loot = getPlayerLoot(_character:getPlayerNum())
    if loot ~= nil and loot.inventoryPane ~= nil and isWorldContainer(loot.inventoryPane.inventory) then
        return loot.inventoryPane.inventory
    end

    local square = _character:getCurrentSquare()
    if square == nil then return nil end

    local cell = getCell()
    local best = nil
    local bestDistance = nil

    for dx = -NEARBY_RADIUS, NEARBY_RADIUS do
        for dy = -NEARBY_RADIUS, NEARBY_RADIUS do
            local other = cell:getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
            if other ~= nil then
                local objects = other:getObjects()
                for i = 0, objects:size() - 1 do
                    local object = objects:get(i)
                    for j = 0, object:getContainerCount() - 1 do
                        local container = object:getContainerByIndex(j)
                        if container ~= nil then
                            local distance = math.abs(dx) + math.abs(dy)
                            if bestDistance == nil or distance < bestDistance then
                                best = container
                                bestDistance = distance
                            end
                        end
                    end
                end
            end
        end
    end

    return best
end

-- ---------------------------------------------------------------------------
-- stamping the choice onto an action
-- ---------------------------------------------------------------------------

local function describeContainer(_action, _container)
    local object = _container:getParent()
    local square = object ~= nil and object:getSquare() or nil
    if square == nil then return false end

    _action.coopOutputX = square:getX()
    _action.coopOutputY = square:getY()
    _action.coopOutputZ = square:getZ()
    _action.coopOutputType = _container:getType()

    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        if objects:get(i) == object then
            _action.coopOutputObjectIndex = i
            break
        end
    end
    _action.coopOutputContainerIndex = object:getContainerIndex(_container)

    return true
end

-- The destination as it stands right now, including which container is nearby.
function COOPOutput.currentDestination(_character)
    local destination = { coopOutputMode = COOPOutput.getMode() }

    if destination.coopOutputMode == COOPOutput.NEARBY then
        local container = COOPOutput.findNearbyContainer(_character or getPlayer())
        if container == nil or not describeContainer(destination, container) then
            -- nothing to put it in; behave like vanilla rather than dropping it somewhere
            destination.coopOutputMode = COOPOutput.HANDS
        end
    end

    return destination
end

-- Custom fields on a timed action do not reach the server, so the destination is sent
-- over the command channel as well; the server keeps the last one per player.
function COOPOutput.sendDestination(_character)
    local character = _character or getPlayer()
    if character == nil then return nil end

    local destination = COOPOutput.currentDestination(character)
    if isClient() then
        sendClientCommand(character, COOPOutput.MODULE, COOPOutput.COMMAND, destination)
    end
    return destination
end

function COOPOutput.stampAction(_action)
    if _action == nil then return _action end

    local destination = COOPOutput.sendDestination(_action.character)
    if destination == nil then return _action end

    -- single player reads these straight off the action
    for key, value in pairs(destination) do
        _action[key] = value
    end

    return _action
end

-- ---------------------------------------------------------------------------
-- the drop-down
-- ---------------------------------------------------------------------------

local function onComboChanged(_target, _combo)
    local chosen = _combo:getOptionData(_combo.selected)
    if chosen ~= nil then COOPOutput.setMode(chosen) end
end

-- Builds a picker bound to the global setting. The owner adds and positions it.
function COOPOutput.newCombo(_x, _y, _width)
    local combo = ISComboBox:new(_x, _y, _width, BUTTON_HGT, nil, onComboChanged)
    combo.font = UIFont.Small
    combo:initialise()
    combo:instantiate()
    -- ISComboBox shows a tooltip per option, not per box
    combo:addOptionWithData(getText("UI_COOP_Output_Hands"), COOPOutput.HANDS,
            getText("UI_COOP_Output_Hands_tt"))
    combo:addOptionWithData(getText("UI_COOP_Output_Bag"), COOPOutput.BAG,
            getText("UI_COOP_Output_Bag_tt"))
    combo:addOptionWithData(getText("UI_COOP_Output_Nearby"), COOPOutput.NEARBY,
            getText("UI_COOP_Output_Nearby_tt"))
    combo:addOptionWithData(getText("UI_COOP_Output_Ground"), COOPOutput.GROUND,
            getText("UI_COOP_Output_Ground_tt"))
    combo:selectData(COOPOutput.getMode())
    table.insert(combos, combo)
    return combo
end

-- ---------------------------------------------------------------------------
-- hooks
-- ---------------------------------------------------------------------------

-- Our own installed functions, so we can tell whether they are still in place: the
-- game re-runs its own class files after a mod requires them, which replaces the class
-- table and drops anything a mod attached to it. See COOP_Output.lua.
local installed = {}

local function hook(_class, _name, _key, _make)
    if _class == nil then return false end
    if installed[_key] ~= nil and _class[_name] == installed[_key] then return false end

    local original = _class[_name]
    if original == nil then return false end

    local wrapper = _make(original)
    _class[_name] = wrapper
    installed[_key] = wrapper
    return true
end

local function install()
    local any = false

    -- ---- crafting window --------------------------------------------------
    any = hook(ISWidgetHandCraftControl, "createChildren", "craftChildren", function(_original)
        return function(self)
            _original(self)
            self.coopOutputCombo = COOPOutput.newCombo(UI_BORDER_SPACING + 1, 0, 100)
            self:addChild(self.coopOutputCombo)
        end
    end) or any

    -- This widget uses a tighter spacing than the rest of the UI.
    local CRAFT_SPACING = 5

    any = hook(ISWidgetHandCraftControl, "calculateLayout", "craftLayout", function(originalCalculateLayout)
      return function(self, _preferredWidth, _preferredHeight)
        local combo = self.coopOutputCombo
        if combo == nil then
            return originalCalculateLayout(self, _preferredWidth, _preferredHeight)
        end

        local extra = BUTTON_HGT + CRAFT_SPACING

        -- Lay the vanilla content out in the height we were given minus one row, then
        -- claim that row. Subtracting first keeps it stable: the table layout measures
        -- with 0 and then lays out again with whatever height we reported.
        originalCalculateLayout(self, _preferredWidth, math.max(0, (_preferredHeight or 0) - extra))

        -- combo takes the Craft button's row, Craft moves down into the new one
        local craftY = self.buttonCraft:getY()
        combo:setX(self.buttonCraft:getX())
        combo:setY(craftY)
        combo:setWidth(self.buttonCraft:getWidth())

        self.buttonCraft:setY(craftY + extra)
        if self.buttonForceCraft then
            self.buttonForceCraft:setY(self.buttonForceCraft:getY() + extra)
        end
        if self.buttonKnowAllRecipes then
            self.buttonKnowAllRecipes:setY(self.buttonKnowAllRecipes:getY() + extra)
        end

        self:setHeight(self:getHeight() + extra)
        self.boxHeight = self:getHeight()
      end
    end) or any

    -- ---- vehicle mechanics window ----------------------------------------
    any = hook(ISVehicleMechanics, "createChildren", "mechanicsChildren", function(_original)
      return function(self)
        _original(self)
        if self.listbox == nil then return end

        local row = BUTTON_HGT + UI_BORDER_SPACING
        self.listbox:setHeight(self.listbox:getHeight() - row)
        if self.bodyworklist ~= nil then
            self.bodyworklist:setHeight(self.bodyworklist:getHeight() - row)
        end

        local width = self.listbox:getWidth()
        if self.bodyworklist ~= nil then
            width = self.bodyworklist:getRight() - self.listbox:getX()
        end

        local combo = COOPOutput.newCombo(self.listbox:getX(), self.listbox:getBottom() + UI_BORDER_SPACING, width)
        combo:setAnchorTop(false)
        combo:setAnchorBottom(true)
        combo:setAnchorLeft(true)
        self:addChild(combo)
        self.coopOutputCombo = combo
      end
    end) or any

    -- ---- stamp the destination onto every action --------------------------
    any = hook(ISHandcraftAction, "FromLogic", "fromLogic", function(_original)
        return function(_logic, _eatPercentage)
            return COOPOutput.stampAction(_original(_logic, _eatPercentage))
        end
    end) or any

    any = hook(ISHandcraftAction, "FromLogicMultiple", "fromLogicMultiple", function(_original)
        return function(_logic)
            return COOPOutput.stampAction(_original(_logic))
        end
    end) or any

    any = hook(ISUninstallVehiclePart, "new", "uninstallNew", function(_original)
        return function(self, _character, _part, _workTime)
            return COOPOutput.stampAction(_original(self, _character, _part, _workTime))
        end
    end) or any

    any = hook(ISTakeEngineParts, "new", "takeEnginePartsNew", function(_original)
        return function(self, _character, _part, _item, _workTime)
            return COOPOutput.stampAction(_original(self, _character, _part, _item, _workTime))
        end
    end) or any

    if any then
        COOP.log("output picker installed, current setting: " .. tostring(COOPOutput.getMode()))
    end
end

install()
Events.OnGameBoot.Add(install)
Events.OnGameStart.Add(install)

-- let the server know where this player wants things as soon as we are in the world
Events.OnGameStart.Add(function() COOPOutput.sendDestination() end)
Events.OnCreatePlayer.Add(function() COOPOutput.sendDestination() end)
