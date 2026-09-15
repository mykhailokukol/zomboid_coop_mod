--
-- CO-OP - the "where do new items go" picker.
--
-- Global settings, saved next to the game's other .ini files, so they hold for every
-- character and every server on this machine. There is one destination per kind of work
-- - cooking, carpentry, car mechanics, smithing - plus a default one that catches
-- everything else; a category left on "same as default" simply follows that default.
--
-- The same picker appears in the crafting window and in the vehicle mechanics window:
-- a category drop-down and a destination drop-down. In the crafting window the category
-- follows whatever recipe is selected, so the destination shown is always the one that
-- recipe will actually use; it can still be changed by hand to edit another category.
-- Changing anything in one window updates every other open picker right away.
--

if isServer() then return end

require "COOP_Common"
require "COOP_Output"

local OPTIONS_FILE = "coop_options.ini"
-- the default category kept the original key, so an existing coop_options.ini still reads
local OPTION_KEYS = {
    [COOPOutput.DEFAULT_CATEGORY] = "outputMode",
    [COOPOutput.COOKING] = "outputMode_cooking",
    [COOPOutput.CARPENTRY] = "outputMode_carpentry",
    [COOPOutput.MECHANICS] = "outputMode_mechanics",
    [COOPOutput.SMITHING] = "outputMode_smithing",
}

local UI_BORDER_SPACING = 10
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BUTTON_HGT = FONT_HGT_SMALL + 6
local NEARBY_RADIUS = 2
local PICKER_GAP = 4
-- how much of the picker the category drop-down takes
local CATEGORY_SHARE = 0.42
local CATEGORY_MAX_WIDTH = 130

local modes = nil
local pickers = {}

local CATEGORY_TEXT = {
    [COOPOutput.DEFAULT_CATEGORY] = "UI_COOP_Output_Cat_Default",
    [COOPOutput.COOKING] = "UI_COOP_Output_Cat_Cooking",
    [COOPOutput.CARPENTRY] = "UI_COOP_Output_Cat_Carpentry",
    [COOPOutput.MECHANICS] = "UI_COOP_Output_Cat_Mechanics",
    [COOPOutput.SMITHING] = "UI_COOP_Output_Cat_Smithing",
}

-- every category the picker offers, default first
local ALL_CATEGORIES = { COOPOutput.DEFAULT_CATEGORY }
for _, category in ipairs(COOPOutput.CATEGORIES) do
    table.insert(ALL_CATEGORIES, category)
end

-- ---------------------------------------------------------------------------
-- the settings
-- ---------------------------------------------------------------------------

local function isCategory(_category)
    return OPTION_KEYS[_category] ~= nil
end

local function load()
    modes = { [COOPOutput.DEFAULT_CATEGORY] = COOPOutput.HANDS }
    for _, category in ipairs(COOPOutput.CATEGORIES) do
        modes[category] = COOPOutput.GLOBAL
    end

    local byKey = {}
    for category, key in pairs(OPTION_KEYS) do byKey[key] = category end

    pcall(function()
        local reader = getFileReader(OPTIONS_FILE, false)
        if reader == nil then return end
        while true do
            local line = reader:readLine()
            if line == nil then break end
            local key, value = string.match(string.trim(line), "^([%w_]+)%s*=%s*(%S+)$")
            local category = key ~= nil and byKey[key] or nil
            if category ~= nil then
                if COOPOutput.isModeValid(value) then
                    modes[category] = value
                elseif value == COOPOutput.GLOBAL and category ~= COOPOutput.DEFAULT_CATEGORY then
                    modes[category] = COOPOutput.GLOBAL
                end
            end
        end
        reader:close()
    end)
end

local function save()
    pcall(function()
        local writer = getFileWriter(OPTIONS_FILE, true, false)
        if writer == nil then return end
        for _, category in ipairs(ALL_CATEGORIES) do
            writer:write(OPTION_KEYS[category] .. "=" .. tostring(modes[category]) .. "\r\n")
        end
        writer:close()
    end)
end

-- What the setting literally says: a destination, or COOPOutput.GLOBAL for a category
-- that is still following the default one.
function COOPOutput.getMode(_category)
    if modes == nil then load() end
    local category = _category or COOPOutput.DEFAULT_CATEGORY
    if not isCategory(category) then category = COOPOutput.DEFAULT_CATEGORY end
    return modes[category]
end

-- The destination that category really ends up using.
function COOPOutput.getEffectiveMode(_category)
    local mode = COOPOutput.getMode(_category)
    if COOPOutput.isModeValid(mode) then return mode end
    return COOPOutput.getMode(COOPOutput.DEFAULT_CATEGORY)
end

function COOPOutput.setMode(_category, _mode)
    local category = _category or COOPOutput.DEFAULT_CATEGORY
    if not isCategory(category) then return end

    local allowGlobal = category ~= COOPOutput.DEFAULT_CATEGORY
    if not COOPOutput.isModeValid(_mode) and not (allowGlobal and _mode == COOPOutput.GLOBAL) then
        return
    end
    if COOPOutput.getMode(category) == _mode then return end

    modes[category] = _mode
    save()
    COOP.log("new items (" .. category .. ") now go to: " .. _mode)
    COOPOutput.sendDestinations()

    -- keep every open picker in step, and forget the ones whose window is gone
    local alive = {}
    for _, picker in ipairs(pickers) do
        if picker ~= nil and picker.parent ~= nil then
            picker:refresh()
            table.insert(alive, picker)
        end
    end
    pickers = alive
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

local function describeContainer(_destination, _container)
    local object = _container:getParent()
    local square = object ~= nil and object:getSquare() or nil
    if square == nil then return false end

    _destination.coopOutputX = square:getX()
    _destination.coopOutputY = square:getY()
    _destination.coopOutputZ = square:getZ()
    _destination.coopOutputType = _container:getType()

    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        if objects:get(i) == object then
            _destination.coopOutputObjectIndex = i
            break
        end
    end
    _destination.coopOutputContainerIndex = object:getContainerIndex(_container)

    return true
end

-- Every category's destination as it stands right now, including which container is
-- nearby. The nearby container is the same for all of them, so it is resolved once.
function COOPOutput.currentDestinations(_character)
    local character = _character or getPlayer()

    local nearby = nil
    local nearbyResolved = false

    local function destinationFor(_mode)
        local destination = { coopOutputMode = _mode }
        if _mode == COOPOutput.NEARBY then
            if not nearbyResolved then
                nearby = COOPOutput.findNearbyContainer(character)
                nearbyResolved = true
            end
            if nearby == nil or not describeContainer(destination, nearby) then
                -- nothing to put it in; behave like vanilla rather than dropping it somewhere
                destination.coopOutputMode = COOPOutput.HANDS
            end
        end
        return destination
    end

    local destinations = {}
    for _, category in ipairs(ALL_CATEGORIES) do
        destinations[category] = destinationFor(COOPOutput.getEffectiveMode(category))
    end
    return destinations
end

-- Custom fields on a timed action do not reach the server, so the set is sent over the
-- command channel as well; the server keeps the last one per player.
function COOPOutput.sendDestinations(_character)
    local character = _character or getPlayer()
    if character == nil then return nil end

    local destinations = COOPOutput.currentDestinations(character)
    if isClient() then
        sendClientCommand(character, COOPOutput.MODULE, COOPOutput.COMMAND, destinations)
    end
    return destinations
end

function COOPOutput.stampAction(_action)
    if _action == nil then return _action end

    local destinations = COOPOutput.sendDestinations(_action.character)
    -- single player reads this straight off the action; it never crosses the wire
    if destinations ~= nil then _action.coopOutputDestinations = destinations end

    return _action
end

-- ---------------------------------------------------------------------------
-- the picker: which kind of work, and where its output goes
-- ---------------------------------------------------------------------------

COOPOutputPicker = ISPanel:derive("COOPOutputPicker")

local function newCombo(_target, _onChange)
    local combo = ISComboBox:new(0, 0, 10, BUTTON_HGT, _target, _onChange)
    combo.font = UIFont.Small
    combo:initialise()
    combo:instantiate()
    return combo
end

-- ISComboBox shows a tooltip per option, not per box.
local function fillDestinations(_combo, _category)
    _combo:clear()
    _combo.selected = 0

    if _category ~= COOPOutput.DEFAULT_CATEGORY then
        _combo:addOptionWithData(getText("UI_COOP_Output_Global"), COOPOutput.GLOBAL,
                getText("UI_COOP_Output_Global_tt"))
    end
    _combo:addOptionWithData(getText("UI_COOP_Output_Hands"), COOPOutput.HANDS,
            getText("UI_COOP_Output_Hands_tt"))
    _combo:addOptionWithData(getText("UI_COOP_Output_Bag"), COOPOutput.BAG,
            getText("UI_COOP_Output_Bag_tt"))
    _combo:addOptionWithData(getText("UI_COOP_Output_Nearby"), COOPOutput.NEARBY,
            getText("UI_COOP_Output_Nearby_tt"))
    _combo:addOptionWithData(getText("UI_COOP_Output_Ground"), COOPOutput.GROUND,
            getText("UI_COOP_Output_Ground_tt"))
end

function COOPOutputPicker:onCategoryChanged(_combo)
    local chosen = _combo:getOptionData(_combo.selected)
    if chosen == nil then return end
    self:setCategory(chosen)
end

function COOPOutputPicker:onDestinationChanged(_combo)
    local chosen = _combo:getOptionData(_combo.selected)
    if chosen ~= nil then COOPOutput.setMode(self.category, chosen) end
end

-- Shows this category and the destination it is set to.
function COOPOutputPicker:setCategory(_category)
    if not isCategory(_category) then _category = COOPOutput.DEFAULT_CATEGORY end

    local changed = self.category ~= _category
    self.category = _category
    self.categoryCombo:selectData(_category)

    -- the "same as default" option only exists for the four real categories
    if changed then fillDestinations(self.destinationCombo, _category) end
    self:refresh()
end

function COOPOutputPicker:refresh()
    self.destinationCombo:selectData(COOPOutput.getMode(self.category))
end

function COOPOutputPicker:reflow()
    if self.categoryCombo == nil then return end

    local width = self:getWidth()
    local categoryWidth = math.min(CATEGORY_MAX_WIDTH, math.floor(width * CATEGORY_SHARE))
    if categoryWidth > width then categoryWidth = width end

    self.categoryCombo:setX(0)
    self.categoryCombo:setY(0)
    self.categoryCombo:setWidth(categoryWidth)

    self.destinationCombo:setX(categoryWidth + PICKER_GAP)
    self.destinationCombo:setY(0)
    self.destinationCombo:setWidth(math.max(0, width - categoryWidth - PICKER_GAP))
end

function COOPOutputPicker:setWidth(_width)
    ISPanel.setWidth(self, _width)
    self:reflow()
end

function COOPOutputPicker:createChildren()
    ISPanel.createChildren(self)

    self.categoryCombo = newCombo(self, COOPOutputPicker.onCategoryChanged)
    for _, category in ipairs(ALL_CATEGORIES) do
        self.categoryCombo:addOptionWithData(getText(CATEGORY_TEXT[category]), category,
                getText("UI_COOP_Output_Cat_tt"))
    end
    self:addChild(self.categoryCombo)

    self.destinationCombo = newCombo(self, COOPOutputPicker.onDestinationChanged)
    self:addChild(self.destinationCombo)

    self.category = nil
    self:setCategory(COOPOutput.DEFAULT_CATEGORY)
    self:reflow()
end

-- Builds a picker bound to the global settings. The owner adds and positions it.
function COOPOutput.newPicker(_x, _y, _width, _category)
    local picker = COOPOutputPicker:new(_x, _y, _width, BUTTON_HGT)
    picker:noBackground()
    picker:initialise()
    picker:instantiate()
    if _category ~= nil then picker:setCategory(_category) end
    table.insert(pickers, picker)
    return picker
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
            if not COOP.featureEnabled(COOP.F_OUTPUT) then return end
            self.coopOutputPicker = COOPOutput.newPicker(UI_BORDER_SPACING + 1, 0, 100)
            self:addChild(self.coopOutputPicker)
        end
    end) or any

    -- The category follows the selected recipe, so the destination on show is the one
    -- that recipe will use. Only when the recipe actually changes, so that picking a
    -- category by hand to edit it is not immediately undone.
    any = hook(ISWidgetHandCraftControl, "prerender", "craftPrerender", function(_original)
        return function(self)
            local picker = self.coopOutputPicker
            if picker ~= nil then
                local recipe = nil
                if self.logic ~= nil then
                    pcall(function() recipe = self.logic:getRecipe() end)
                end
                if picker.coopRecipe ~= recipe then
                    picker.coopRecipe = recipe
                    picker:setCategory(COOPOutput.categoryForRecipe(recipe))
                end
            end
            return _original(self)
        end
    end) or any

    -- This widget uses a tighter spacing than the rest of the UI.
    local CRAFT_SPACING = 5

    any = hook(ISWidgetHandCraftControl, "calculateLayout", "craftLayout", function(originalCalculateLayout)
      return function(self, _preferredWidth, _preferredHeight)
        local picker = self.coopOutputPicker
        if picker == nil then
            return originalCalculateLayout(self, _preferredWidth, _preferredHeight)
        end

        local extra = BUTTON_HGT + CRAFT_SPACING

        -- Lay the vanilla content out in the height we were given minus one row, then
        -- claim that row. Subtracting first keeps it stable: the table layout measures
        -- with 0 and then lays out again with whatever height we reported.
        originalCalculateLayout(self, _preferredWidth, math.max(0, (_preferredHeight or 0) - extra))

        -- picker takes the Craft button's row, Craft moves down into the new one
        local craftY = self.buttonCraft:getY()
        picker:setX(self.buttonCraft:getX())
        picker:setY(craftY)
        picker:setWidth(self.buttonCraft:getWidth())

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
        if not COOP.featureEnabled(COOP.F_OUTPUT) then return end

        local row = BUTTON_HGT + UI_BORDER_SPACING
        self.listbox:setHeight(self.listbox:getHeight() - row)
        if self.bodyworklist ~= nil then
            self.bodyworklist:setHeight(self.bodyworklist:getHeight() - row)
        end

        local width = self.listbox:getWidth()
        if self.bodyworklist ~= nil then
            width = self.bodyworklist:getRight() - self.listbox:getX()
        end

        -- nothing here is a recipe, so the category stays on car mechanics
        local picker = COOPOutput.newPicker(self.listbox:getX(),
                self.listbox:getBottom() + UI_BORDER_SPACING, width, COOPOutput.MECHANICS)
        picker:setAnchorTop(false)
        picker:setAnchorBottom(true)
        picker:setAnchorLeft(true)
        self:addChild(picker)
        self.coopOutputPicker = picker
      end
    end) or any

    -- ---- stamp the destinations onto every action -------------------------
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

    -- The parameter names below are NOT the mod's usual _underscore style on purpose,
    -- and they must keep matching the vanilla ones exactly. In multiplayer the engine
    -- ships a timed action to the server by reflecting over the class's `new`:
    -- NetTimedAction.set() takes new's Prototype, walks locvars[0..numParams-1], and for
    -- each parameter name rawgets a field of that name off the action instance. Vanilla
    -- names (character, part, workTime) line up with o.character / o.part / o.workTime;
    -- renaming them to _character/_part/_workTime made every argument come across as
    -- null, the server rebuilt the action as ISUninstallVehiclePart:new(nil, nil, nil),
    -- its complete() printed "no such vehicle id= nil", the transaction was rejected and
    -- the client force-stopped the action a moment after it started.
    any = hook(ISUninstallVehiclePart, "new", "uninstallNew", function(_original)
        return function(self, character, part, workTime)
            return COOPOutput.stampAction(_original(self, character, part, workTime))
        end
    end) or any

    any = hook(ISTakeEngineParts, "new", "takeEnginePartsNew", function(_original)
        return function(self, character, part, item, workTime)
            return COOPOutput.stampAction(_original(self, character, part, item, workTime))
        end
    end) or any

    if any then
        COOP.log("output picker installed, default destination: "
                .. tostring(COOPOutput.getMode()))
    end
end

install()
Events.OnGameBoot.Add(install)
Events.OnGameStart.Add(install)

-- let the server know where this player wants things as soon as we are in the world
Events.OnGameStart.Add(function() COOPOutput.sendDestinations() end)
Events.OnCreatePlayer.Add(function() COOPOutput.sendDestinations() end)
