--
-- CO-OP - the concrete mixer's window and menus.
--
-- One window for both of the mixer's containers: the water it holds and the items in
-- the drum, with the cement recipes underneath. It is a view - every change is a
-- vanilla timed action (item transfer, fluid transfer) or a request to the server, so
-- nothing here has to be told about multiplayer.
--
-- Picking the mixer up goes through the vanilla moveables system rather than a hand
-- rolled action: ISMoveableSpriteProps already knows how to turn a world object into an
-- item, how to sync that, and - because the sprite is marked IsWaterCollector - that it
-- must refuse while the drum still holds water or anything else.
--

if isServer() then return end

require "ISUI/ISCollapsableWindow"
require "TimedActions/ISBaseTimedAction"
require "COOP_Mixer"

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local UI_BORDER_SPACING = 10
local BUTTON_HGT = FONT_HGT_SMALL + 6
local ROW_HGT = FONT_HGT_SMALL + 10
local BAR_HGT = FONT_HGT_SMALL + 4

local COLOR_WATER = { r = 0.30, g = 0.55, b = 0.85 }
local COLOR_LOAD = { r = 0.75, g = 0.65, b = 0.35 }
local COLOR_DIM = { r = 0.62, g = 0.62, b = 0.62 }

-- --------------------------------------------------------------------------
-- what the player is carrying
-- --------------------------------------------------------------------------

-- Every container the player has on them: their hands and pockets, plus each worn bag.
local function carriedContainers(_player)
    local list = { _player:getInventory() }

    local worn = _player:getWornItems()
    if worn ~= nil then
        for i = 0, worn:size() - 1 do
            local item = worn:getItemByIndex(i)
            if item ~= nil and instanceof(item, "InventoryContainer") then
                local inventory = item:getInventory()
                if inventory ~= nil then table.insert(list, inventory) end
            end
        end
    end

    return list
end

-- Carried items grouped by type: { {type, name, count, item, container}, ... }, sorted
-- by name. One entry per type keeps the menu short when someone is hauling 40 clay.
local function carriedByType(_player, _accepts)
    local byType = {}
    local order = {}

    -- worn clothing and the bags themselves sit in the main inventory alongside
    -- everything else, and nobody wants to tip their trousers into a concrete mixer
    local function carried(_item)
        local ok, equipped = pcall(function()
            return _player:isEquipped(_item) or _player:isEquippedClothing(_item)
        end)
        return not (ok and equipped)
    end

    for _, container in ipairs(carriedContainers(_player)) do
        local items = container:getItems()
        if items ~= nil then
            for i = 0, items:size() - 1 do
                local item = items:get(i)
                if item ~= nil and carried(item) and (_accepts == nil or _accepts(item)) then
                    local fullType = item:getFullType()
                    local entry = byType[fullType]
                    if entry == nil then
                        entry = {
                            type = fullType,
                            name = item:getName(),
                            count = 0,
                            item = item,
                            container = container,
                        }
                        byType[fullType] = entry
                        table.insert(order, entry)
                    end
                    entry.count = entry.count + 1
                end
            end
        end
    end

    table.sort(order, function(_a, _b) return _a.name < _b.name end)
    return order
end

-- The water an item is holding, or nil when it is not a fluid container at all.
local function waterInItem(_item)
    local ok, amount = pcall(function()
        local fluid = _item:getFluidContainer()
        if fluid == nil then return nil end
        if fluid:getAmount() <= 0 then return 0 end
        if not fluid:isWaterSource() then return nil end
        return fluid:getAmount()
    end)
    if ok then return amount end
    return nil
end

local function itemFluidContainer(_item)
    local ok, fluid = pcall(function() return _item:getFluidContainer() end)
    if ok then return fluid end
    return nil
end

-- --------------------------------------------------------------------------
-- the window
-- --------------------------------------------------------------------------

COOPMixerWindow = ISCollapsableWindow:derive("COOPMixerWindow")
COOPMixerWindow.instance = nil

local function drawRow(self, y, item, alt)
    if item.height == nil then item.height = ROW_HGT end
    if (y + self:getYScroll() + item.height < 0) or (y + self:getYScroll() >= self.height) then
        return y + item.height
    end

    local width = self:getWidth()
    if self.selected == item.index then
        self:drawRect(0, y, width, item.height - 1, 0.25, 0.6, 0.5, 0.25)
    elseif self.mouseoverselected == item.index and self:isMouseOver() and not self:isMouseOverScrollBar() then
        self:drawRect(0, y, width, item.height - 1, 0.12, 1, 1, 1)
    end

    local entry = item.item
    self:drawText(entry.name, 8, y + 5, 1, 1, 1, 1, UIFont.Small)

    local weight = string.format("%.1f", entry.weight)
    local weightWidth = getTextManager():MeasureStringX(UIFont.Small, weight)
    self:drawText(weight, width - 12 - weightWidth, y + 5, COLOR_DIM.r, COLOR_DIM.g, COLOR_DIM.b, 1, UIFont.Small)

    return y + item.height
end

function COOPMixerWindow:addButton(_x, _y, _text, _onclick)
    local width = getTextManager():MeasureStringX(UIFont.Small, _text) + 20
    local btn = ISButton:new(_x, _y, width, BUTTON_HGT, _text, self, _onclick)
    btn:initialise()
    btn:instantiate()
    self:addChild(btn)
    return btn
end

function COOPMixerWindow:createChildren()
    ISCollapsableWindow.createChildren(self)

    local x = UI_BORDER_SPACING
    local listY = self:titleBarHeight() + UI_BORDER_SPACING + (BAR_HGT + 4) * 2 + UI_BORDER_SPACING
    local listH = self.height - listY - BUTTON_HGT - UI_BORDER_SPACING * 2

    self.list = ISScrollingListBox:new(x, listY, self.width - x * 2, listH)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = ROW_HGT
    self.list.font = UIFont.Small
    self.list.drawBorder = true
    self.list.doDrawItem = drawRow
    self:addChild(self.list)

    local by = self.height - UI_BORDER_SPACING - BUTTON_HGT
    self.btnAdd = self:addButton(x, by, getText("UI_COOP_Mixer_Add"), COOPMixerWindow.onAdd)
    self.btnTake = self:addButton(self.btnAdd:getRight() + 4, by, getText("UI_COOP_Mixer_Take"), COOPMixerWindow.onTake)

    local mixLabel = getText("UI_COOP_Mixer_Mix")
    local mixWidth = getTextManager():MeasureStringX(UIFont.Small, mixLabel) + 20
    self.btnMix = ISButton:new(self.width - UI_BORDER_SPACING - mixWidth, by, mixWidth, BUTTON_HGT,
            mixLabel, self, COOPMixerWindow.onMix)
    self.btnMix:initialise()
    self.btnMix:instantiate()
    self:addChild(self.btnMix)

    self:refreshList()
end

function COOPMixerWindow:onResize()
    ISCollapsableWindow.onResize(self)

    local by = self.height - UI_BORDER_SPACING - BUTTON_HGT
    self.list:setWidth(self.width - UI_BORDER_SPACING * 2)
    self.list:setHeight(by - UI_BORDER_SPACING - self.list:getY())

    self.btnAdd:setY(by)
    self.btnTake:setY(by)
    self.btnTake:setX(self.btnAdd:getRight() + 4)
    self.btnMix:setY(by)
    self.btnMix:setX(self.width - UI_BORDER_SPACING - self.btnMix:getWidth())
end

-- A cheap stand-in for "did anything change": how much is in each container. Rebuilding
-- the list every frame would fight the player's selection.
function COOPMixerWindow:signature()
    local water = COOPMixer.getWater(self.object)
    local container = COOPMixer.getContainer(self.object)
    local count = 0
    if container ~= nil then
        local items = container:getItems()
        count = items ~= nil and items:size() or 0
    end
    return string.format("%.3f|%d", water, count)
end

function COOPMixerWindow:refreshList()
    self.sig = self:signature()

    local selected = self.list.selected
    self.list:clear()

    local container = COOPMixer.getContainer(self.object)
    if container == nil then return end

    local items = container:getItems()
    if items == nil then return end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item ~= nil then
            self.list:addItem(item:getName(), {
                name = item:getName(),
                weight = item:getUnequippedWeight(),
                item = item,
            })
        end
    end

    if selected and selected <= #self.list.items then
        self.list.selected = selected
    end
end

function COOPMixerWindow:selectedItem()
    local row = self.list.items[self.list.selected]
    if row == nil then return nil end
    return row.item.item
end

-- --------------------------------------------------------------------------
-- the two bars
-- --------------------------------------------------------------------------

function COOPMixerWindow:drawBar(_y, _label, _value, _max, _colour, _suffix)
    local x = UI_BORDER_SPACING
    local width = self.width - x * 2

    local labelWidth = getTextManager():MeasureStringX(UIFont.Small, _label) + 8
    self:drawText(_label, x, _y + 2, 0.85, 0.85, 0.85, 1, UIFont.Small)

    local barX = x + labelWidth
    local barWidth = width - labelWidth

    self:drawRect(barX, _y, barWidth, BAR_HGT, 0.35, 0, 0, 0)
    if _max > 0 and _value > 0 then
        local filled = math.min(1, _value / _max) * barWidth
        self:drawRect(barX, _y, filled, BAR_HGT, 0.9, _colour.r, _colour.g, _colour.b)
    end
    self:drawRectBorder(barX, _y, barWidth, BAR_HGT, 0.5, 0.6, 0.6, 0.6)

    local text = string.format("%.1f / %.0f%s", _value, _max, _suffix or "")
    local textWidth = getTextManager():MeasureStringX(UIFont.Small, text)
    self:drawText(text, barX + barWidth - textWidth - 6, _y + 2, 1, 1, 1, 1, UIFont.Small)
end

function COOPMixerWindow:prerender()
    ISCollapsableWindow.prerender(self)

    local y = self:titleBarHeight() + UI_BORDER_SPACING
    local water, waterMax = COOPMixer.getWater(self.object)
    local load, loadMax = COOPMixer.getLoad(self.object)

    self:drawBar(y, getText("UI_COOP_Mixer_Water"), water, waterMax, COLOR_WATER, "")
    self:drawBar(y + BAR_HGT + 4, getText("UI_COOP_Mixer_Load"), load, loadMax, COLOR_LOAD, " kg")
end

-- --------------------------------------------------------------------------
-- putting things in and taking them out
-- --------------------------------------------------------------------------

function COOPMixerWindow:menuAt(_button)
    local menu = ISContextMenu.get(self.playerNum,
            self:getAbsoluteX() + _button:getX(),
            self:getAbsoluteY() + _button:getY() + _button:getHeight())
    return menu
end

local function disable(_option, _reason)
    if _option == nil then return end
    _option.notAvailable = true
    if _reason ~= nil and ISWorldObjectContextMenu and ISWorldObjectContextMenu.addToolTip then
        local tooltip = ISWorldObjectContextMenu.addToolTip()
        tooltip.description = _reason
        _option.toolTip = tooltip
    end
end

function COOPMixerWindow:onAdd()
    local player = getSpecificPlayer(self.playerNum)
    if player == nil then return end

    -- an older save can hold a mixer that was written before this mod gave the sprite
    -- its containers; build them now rather than showing an empty menu
    COOPMixer.prepare(self.object)

    local container = COOPMixer.getContainer(self.object)
    local menu = self:menuAt(self.btnAdd)
    local added = 0

    -- The water half does not need the item container, so it is offered either way.
    if container == nil then
        disable(menu:addOption(getText("UI_COOP_Mixer_NoDrum")), getText("UI_COOP_Mixer_NoDrum_tt"))
    end

    for _, entry in ipairs(carriedByType(player)) do
        if container == nil then break end

        local label = entry.name
        if entry.count > 1 then label = label .. " (" .. entry.count .. ")" end

        local option = menu:addOption(label, self, COOPMixerWindow.onAddItem, entry)
        if not container:hasRoomFor(player, entry.item) then
            disable(option, getText("UI_COOP_Mixer_Full"))
        end
        added = added + 1
    end

    -- water goes in from anything carrying some
    for _, entry in ipairs(carriedByType(player, function(_item) return (waterInItem(_item) or 0) > 0 end)) do
        local amount = waterInItem(entry.item) or 0
        local option = menu:addOption(
                getText("UI_COOP_Mixer_PourIn", entry.name, string.format("%.1f", amount)),
                self, COOPMixerWindow.onPourIn, entry.item)
        local water, waterMax = COOPMixer.getWater(self.object)
        if water >= waterMax then disable(option, getText("UI_COOP_Mixer_FullWater")) end
        added = added + 1
    end

    if added == 0 then
        disable(menu:addOption(getText("UI_COOP_Mixer_NothingToAdd")), nil)
    end
end

function COOPMixerWindow:onAddItem(_entry)
    local player = getSpecificPlayer(self.playerNum)
    local container = COOPMixer.getContainer(self.object)
    if player == nil or container == nil or _entry == nil then return end
    if not self:walkToMixer(player) then return end

    ISTimedActionQueue.add(ISInventoryTransferAction:new(player, _entry.item, _entry.container, container))
end

function COOPMixerWindow:onTake()
    local player = getSpecificPlayer(self.playerNum)
    if player == nil then return end

    local menu = self:menuAt(self.btnTake)
    local selected = self:selectedItem()

    if selected ~= nil then
        menu:addOption(getText("UI_COOP_Mixer_TakeItem", selected:getName()), self,
                COOPMixerWindow.onTakeItem, selected)
    else
        disable(menu:addOption(getText("UI_COOP_Mixer_TakeItem", "...")),
                getText("UI_COOP_Mixer_NothingSelected"))
    end

    -- and water, into anything that will hold it
    local water = COOPMixer.getWater(self.object)
    for _, entry in ipairs(carriedByType(player, function(_item)
        local ok, canStore = pcall(function() return _item:canStoreWater() end)
        if not (ok and canStore) then return false end
        local fluid = itemFluidContainer(_item)
        return fluid ~= nil and fluid:getFreeCapacity() > 0
    end)) do
        local option = menu:addOption(getText("UI_COOP_Mixer_FillFrom", entry.name), self,
                COOPMixerWindow.onDrawWater, entry.item)
        if water <= 0 then disable(option, getText("UI_COOP_Mixer_NoWater")) end
    end
end

function COOPMixerWindow:onTakeItem(_item)
    local player = getSpecificPlayer(self.playerNum)
    local container = COOPMixer.getContainer(self.object)
    if player == nil or container == nil or _item == nil then return end
    if not self:walkToMixer(player) then return end

    ISTimedActionQueue.add(ISInventoryTransferAction:new(player, _item, container, player:getInventory()))
end

-- --------------------------------------------------------------------------
-- water
-- --------------------------------------------------------------------------

-- Both directions are vanilla's, and deliberately so. A plain IsoObject does not hand
-- its FluidContainer to Lua, so ISFluidTransferAction - which wants one at each end -
-- cannot be used here; but ISAddFluidFromItemAction and ISTakeWaterAction both take the
-- object itself, do the pouring on the authoritative side and sync the item afterwards.
-- The two ISWorldObjectContextMenu helpers wrap them with the walking, the equipping and
-- putting the bottle back in the bag it came from.
function COOPMixerWindow:onPourIn(_item)
    local player = getSpecificPlayer(self.playerNum)
    if player == nil or _item == nil then return end

    local ok, err = pcall(function()
        ISWorldObjectContextMenu.onAddFluidFromItem(nil, self.object, _item, player)
    end)
    if not ok then COOP.log("concrete mixer: pouring in failed: " .. tostring(err)) end
end

function COOPMixerWindow:onDrawWater(_item)
    local player = getSpecificPlayer(self.playerNum)
    if player == nil or _item == nil then return end

    local ok, err = pcall(function()
        ISWorldObjectContextMenu.onTakeWater(nil, self.object, nil, _item, self.playerNum)
    end)
    if not ok then COOP.log("concrete mixer: drawing water failed: " .. tostring(err)) end
end

-- --------------------------------------------------------------------------
-- mixing
-- --------------------------------------------------------------------------

function COOPMixerWindow:onMix()
    local menu = self:menuAt(self.btnMix)

    for _, recipe in ipairs(COOPMixer.RECIPES) do
        local option = menu:addOption(getText(recipe.label), self, COOPMixerWindow.onMixRecipe, recipe)
        local ok, missing = COOPMixer.check(self.object, recipe)
        if not ok then
            local parts = {}
            for _, entry in ipairs(missing) do
                table.insert(parts, getText(entry.label) .. " x" .. entry.need)
            end
            disable(option, getText("UI_COOP_Mixer_Missing") .. " " .. table.concat(parts, ", "))
        end
    end
end

function COOPMixerWindow:onMixRecipe(_recipe)
    local player = getSpecificPlayer(self.playerNum)
    if player == nil or _recipe == nil then return end
    if not self:walkToMixer(player) then return end

    ISTimedActionQueue.add(COOPMixerAction:new(player, self.object, _recipe))
end

-- --------------------------------------------------------------------------
-- housekeeping
-- --------------------------------------------------------------------------

function COOPMixerWindow:walkToMixer(_player)
    local square = self.object:getSquare()
    if square == nil then return false end
    if _player:DistToProper(self.object) <= COOPMixer.REACH then return true end
    return luautils.walkAdj(_player, square, false)
end

function COOPMixerWindow:update()
    ISCollapsableWindow.update(self)

    local player = getSpecificPlayer(self.playerNum)
    if player == nil or self.object == nil or not self.object:isExistInTheWorld() then
        self:close()
        return
    end

    -- the mixer can be picked up while its window is open; and walking off should shut it
    if player:DistToProper(self.object) > COOPMixer.REACH + 2 then
        self:close()
        return
    end

    local sig = self:signature()
    if sig ~= self.sig then self:refreshList() end
end

function COOPMixerWindow:isKeyConsumed(_key)
    return _key == Keyboard.KEY_ESCAPE
end

function COOPMixerWindow:onKeyRelease(_key)
    if _key == Keyboard.KEY_ESCAPE and self:getIsVisible() then
        self:close()
    end
end

function COOPMixerWindow:close()
    self:setVisible(false)
    self:removeFromUIManager()
    if COOPMixerWindow.instance == self then COOPMixerWindow.instance = nil end
end

function COOPMixerWindow:new(_x, _y, _width, _height, _player, _object)
    local o = ISCollapsableWindow:new(_x, _y, _width, _height)
    setmetatable(o, self)
    self.__index = self
    o.title = getText("UI_COOP_Mixer_Title")
    o.object = _object
    o.player = _player
    o.playerNum = _player:getPlayerNum()
    o.sig = ""
    o:setResizable(true)
    return o
end

function COOPMixerWindow.open(_player, _object)
    if not COOPMixer.isEnabled() then return end
    if _player == nil or _object == nil then return end

    -- the server keeps the list of mixers the rain tops up, and this is the moment it
    -- learns about this one; in single player COOPMixer.prepare has already done it
    if isClient() then
        local square = _object:getSquare()
        if square ~= nil then
            sendClientCommand(_player, COOPMixer.MODULE, COOPMixer.CMD_SEEN, {
                x = square:getX(), y = square:getY(), z = square:getZ(),
            })
        end
    end

    local existing = COOPMixerWindow.instance
    if existing ~= nil then existing:close() end

    COOPMixer.prepare(_object)

    local width = 420
    local height = 380
    local window = COOPMixerWindow:new((getCore():getScreenWidth() - width) / 2,
            (getCore():getScreenHeight() - height) / 2, width, height, _player, _object)
    window:initialise()
    window:instantiate()
    window:addToUIManager()
    COOPMixerWindow.instance = window
end

Events.OnGameStart.Add(function()
    local window = COOPMixerWindow.instance
    if window ~= nil then
        window:removeFromUIManager()
        COOPMixerWindow.instance = nil
    end
end)

-- --------------------------------------------------------------------------
-- the mixing action
-- --------------------------------------------------------------------------

COOPMixerAction = ISBaseTimedAction:derive("COOPMixerAction")

function COOPMixerAction:isValid()
    return self.object ~= nil and self.object:isExistInTheWorld()
            and self.character:DistToProper(self.object) <= COOPMixer.REACH + 1
end

function COOPMixerAction:waitToStart()
    self.character:faceThisObject(self.object)
    return self.character:shouldBeTurning()
end

function COOPMixerAction:update()
    self.character:faceThisObject(self.object)
    self.character:setMetabolicTarget(Metabolics.MediumWork)
end

function COOPMixerAction:start()
    -- the animation and the sound vanilla's own MixingBucket action uses
    self:setActionAnim("MixingBucket")
    self.sound = self.character:playSound("CraftMakeCement")
end

function COOPMixerAction:stop()
    if self.sound then self.character:stopOrTriggerSound(self.sound) end
    ISBaseTimedAction.stop(self)
end

-- The work is done here and there is deliberately no `complete`. A timed action whose
-- class defines one is shipped to the server and run there as well - the constructor
-- only sets useCustomRemoteTimedActionSync when `complete` is absent - so defining one
-- here would mix the batch twice in multiplayer: once on the rebuilt server-side action
-- and once through the request below.
function COOPMixerAction:perform()
    if self.sound then self.character:stopOrTriggerSound(self.sound) end

    local square = self.object ~= nil and self.object:getSquare() or nil
    if square ~= nil then
        if isClient() then
            -- the mixer's containers belong to the server, so ask rather than write
            sendClientCommand(self.character, COOPMixer.MODULE, COOPMixer.CMD_CRAFT, {
                x = square:getX(), y = square:getY(), z = square:getZ(),
                recipe = self.recipe.id,
            })
        else
            COOPMixer.craft(self.object, self.recipe)
        end
    end

    ISBaseTimedAction.perform(self)
end

function COOPMixerAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return self.recipe.time or 150
end

function COOPMixerAction:new(character, object, recipe)
    local o = ISBaseTimedAction.new(self, character)
    o.object = object
    o.recipe = recipe
    o.maxTime = o:getDuration()
    return o
end

-- --------------------------------------------------------------------------
-- the world context menu
-- --------------------------------------------------------------------------

local function onOpen(_player, _object)
    local square = _object:getSquare()
    if square == nil then return end
    if _player:DistToProper(_object) > COOPMixer.REACH then
        luautils.walkAdj(_player, square, false)
    end
    COOPMixerWindow.open(_player, _object)
end

-- Vanilla's own pick-up, which is reached from the furniture cursor and not from this
-- menu. Everything it needs to know - the 30 kg, the refusal while the drum is not
-- empty - is on the sprite by the time this runs.
local function onPickUp(_player, _object)
    local square = _object:getSquare()
    if square == nil then return end

    local props = ISMoveableSpriteProps.fromObject(_object)
    if props == nil or not props.isMoveable then return end

    if props:walkToAndEquip(_player, square, "pickup", props.spriteName) then
        ISTimedActionQueue.add(ISMoveablesAction:new(_player, square, "pickup",
                props.spriteName, _object, nil, nil, nil))
    end
end

local function onFillWorldObjectContextMenu(_playerNum, _context, _worldobjects, _test)
    if _test and ISWorldObjectContextMenu.Test then return true end
    if not COOPMixer.isEnabled() then return end

    local player = getSpecificPlayer(_playerNum)
    if player == nil or player:getVehicle() ~= nil then return end

    -- The clicked squares, not only the objects the picker handed back: a mixer often
    -- shares its square with rubble and pallets, and the picker answers with one of them.
    local mixer = nil
    for _, object in ipairs(_worldobjects) do
        local square = object:getSquare()
        if square ~= nil and player:DistToProper(object) <= COOPMixer.REACH + 1 then
            mixer = COOPMixer.findOnSquare(square)
            if mixer ~= nil then break end
        end
    end
    if mixer == nil then return end

    if _test then return ISWorldObjectContextMenu.setTest() end

    COOPMixer.prepare(mixer)

    local menu = _context:addOption(getText("ContextMenu_COOP_Mixer"), nil, nil)
    local sub = ISContextMenu:getNew(_context)
    _context:addSubMenu(menu, sub)

    sub:addOption(getText("ContextMenu_COOP_Mixer_Open"), player, onOpen, mixer)

    local option = sub:addOption(getText("ContextMenu_COOP_Mixer_PickUp"), player, onPickUp, mixer)
    local props = ISMoveableSpriteProps.fromObject(mixer)
    if props == nil or not props.isMoveable
            or not props:canPickUpMoveable(player, mixer:getSquare(), mixer) then
        disable(option, getText("ContextMenu_COOP_Mixer_PickUp_tt"))
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
