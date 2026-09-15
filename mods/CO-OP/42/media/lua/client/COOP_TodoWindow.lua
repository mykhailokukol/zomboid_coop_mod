--
-- CO-OP - the shared to-do window.
--
-- A view over COOPTodoState and nothing else: every change goes to the server and comes
-- back as a delta, so two players editing the same line cannot diverge. The window
-- rebuilds itself whenever COOPTodoState.rev moves.
--

if isServer() then return end

require "ISUI/ISCollapsableWindow"
require "COOP_Todo"

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local UI_BORDER_SPACING = 10
local BUTTON_HGT = FONT_HGT_SMALL + 6
local ROW_HGT = FONT_HGT_SMALL * 2 + 10
local BOX_SIZE = 12

local COLOR_DONE = { r = 0.45, g = 0.85, b = 0.45 }
local COLOR_DIM = { r = 0.62, g = 0.62, b = 0.62 }

COOPTodoWindow = ISCollapsableWindow:derive("COOPTodoWindow")
COOPTodoWindow.instance = nil

-- --------------------------------------------------------------------------
-- one row
-- --------------------------------------------------------------------------

local function drawRow(self, y, item, alt)
    if item.height == nil then item.height = ROW_HGT end
    if (y + self:getYScroll() + item.height < 0) or (y + self:getYScroll() >= self.height) then
        return y + item.height
    end

    local entry = item.item
    local done = COOPTodo.isDone(entry)
    local width = self:getWidth()

    if self.selected == item.index then
        self:drawRect(0, y, width, item.height - 1, 0.25, 0.6, 0.5, 0.25)
    elseif self.mouseoverselected == item.index and self:isMouseOver() and not self:isMouseOverScrollBar() then
        self:drawRect(0, y, width, item.height - 1, 0.12, 1, 1, 1)
    end
    self:drawRectBorder(0, y, width, item.height, 0.35, self.borderColor.r, self.borderColor.g, self.borderColor.b)

    -- the tick box, drawn rather than textured so there is no asset to go missing
    local boxX = 8
    local boxY = y + (item.height - BOX_SIZE) / 2
    self:drawRectBorder(boxX, boxY, BOX_SIZE, BOX_SIZE, 0.8, 0.7, 0.7, 0.7)
    if done then
        self:drawRect(boxX + 3, boxY + 3, BOX_SIZE - 6, BOX_SIZE - 6, 1,
                COLOR_DONE.r, COLOR_DONE.g, COLOR_DONE.b)
    end

    local textX = boxX + BOX_SIZE + 8
    local line1 = y + 4
    local line2 = line1 + FONT_HGT_SMALL

    if done then
        self:drawText(entry.text, textX, line1, COLOR_DIM.r, COLOR_DIM.g, COLOR_DIM.b, 1, UIFont.Small)
    else
        self:drawText(entry.text, textX, line1, 1, 1, 1, 1, UIFont.Small)
    end

    local detail = getText("UI_COOP_Todo_AddedBy", entry.by or "?", entry.when or "?")
    if done and entry.doneBy ~= nil then
        detail = detail .. "  -  " .. getText("UI_COOP_Todo_DoneBy", entry.doneBy, entry.doneWhen or "?")
    end
    self:drawText(detail, textX, line2, COLOR_DIM.r, COLOR_DIM.g, COLOR_DIM.b, 1, UIFont.Small)

    return y + item.height
end

-- --------------------------------------------------------------------------
-- window
-- --------------------------------------------------------------------------

function COOPTodoWindow:addButton(_x, _y, _text, _onclick)
    local width = getTextManager():MeasureStringX(UIFont.Small, _text) + 20
    local btn = ISButton:new(_x, _y, width, BUTTON_HGT, _text, self, _onclick)
    btn:initialise()
    btn:instantiate()
    self:addChild(btn)
    return btn
end

function COOPTodoWindow:addFilterButton(_x, _y, _text, _filter)
    local btn = self:addButton(_x, _y, _text, COOPTodoWindow.onFilterButton)
    btn.internal = _filter
    return btn
end

function COOPTodoWindow:createChildren()
    ISCollapsableWindow.createChildren(self)

    local th = self:titleBarHeight()
    local x = UI_BORDER_SPACING
    local y = th + UI_BORDER_SPACING

    self.btnAdd = self:addButton(0, y, getText("UI_COOP_Todo_Add"), COOPTodoWindow.onAdd)

    self.newEntry = ISTextEntryBox:new("", x, y, self.width - x * 2 - self.btnAdd:getWidth() - 4, BUTTON_HGT)
    self.newEntry.font = UIFont.Small
    self.newEntry:initialise()
    self.newEntry:instantiate()
    self.newEntry:setMaxTextLength(COOPTodo.TEXT_MAX)
    self.newEntry.onCommandEntered = function() self:onAdd() end
    self:addChild(self.newEntry)
    self.btnAdd:setX(self.newEntry:getRight() + 4)

    local y2 = y + BUTTON_HGT + 6
    self.btnFilterAll = self:addFilterButton(x, y2, getText("UI_COOP_Todo_FilterAll"), "all")
    self.btnFilterOpen = self:addFilterButton(self.btnFilterAll:getRight() + 4, y2, getText("UI_COOP_Todo_FilterOpen"), "open")
    self.btnFilterDone = self:addFilterButton(self.btnFilterOpen:getRight() + 4, y2, getText("UI_COOP_Todo_FilterDone"), "done")

    local listY = y2 + BUTTON_HGT + UI_BORDER_SPACING
    local listH = self.height - listY - (BUTTON_HGT + UI_BORDER_SPACING * 2) - FONT_HGT_SMALL - 4

    self.list = ISScrollingListBox:new(x, listY, self.width - x * 2, listH)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = ROW_HGT
    self.list.font = UIFont.Small
    self.list.drawBorder = true
    self.list.doDrawItem = drawRow
    self.list:setOnMouseDoubleClick(self, self.onDoubleClick)
    self:addChild(self.list)

    local by = self.height - UI_BORDER_SPACING - BUTTON_HGT
    self.btnToggle = self:addButton(x, by, getText("UI_COOP_Todo_Toggle"), COOPTodoWindow.onToggle)
    self.btnEdit = self:addButton(self.btnToggle:getRight() + 4, by, getText("UI_COOP_Todo_Edit"), COOPTodoWindow.onEdit)
    self.btnRemove = self:addButton(self.btnEdit:getRight() + 4, by, getText("UI_COOP_Todo_Remove"), COOPTodoWindow.onRemove)

    local clearLabel = getText("UI_COOP_Todo_ClearDone")
    local clearWidth = getTextManager():MeasureStringX(UIFont.Small, clearLabel) + 20
    self.btnClear = ISButton:new(self.width - UI_BORDER_SPACING - clearWidth, by, clearWidth, BUTTON_HGT,
            clearLabel, self, COOPTodoWindow.onClearDone)
    self.btnClear:initialise()
    self.btnClear:instantiate()
    self.btnClear:enableCancelColor()
    self:addChild(self.btnClear)

    self:setFilter("all")
    self:refreshList()
end

local function highlight(_buttons, _selected)
    for name, btn in pairs(_buttons) do
        if btn ~= nil then
            btn.backgroundColor.a = (name == _selected) and 0.9 or 0.4
        end
    end
end

function COOPTodoWindow:setFilter(_filter)
    self.filter = _filter
    highlight({ all = self.btnFilterAll, open = self.btnFilterOpen, done = self.btnFilterDone }, _filter)
    self:refreshList()
end

function COOPTodoWindow:onFilterButton(_button)
    self:setFilter(_button.internal)
end

function COOPTodoWindow:selectedEntry()
    local item = self.list.items[self.list.selected]
    if item == nil then return nil end
    return item.item
end

function COOPTodoWindow:onAdd()
    local text = self.newEntry:getText()
    if COOPTodo.cleanText(text) == nil then return end
    COOPTodoState.add(text)
    self.newEntry:setText("")
end

function COOPTodoWindow:onToggle()
    local entry = self:selectedEntry()
    if entry == nil then return end
    COOPTodoState.toggle(entry.id)
end

function COOPTodoWindow:onDoubleClick()
    self:onToggle()
end

function COOPTodoWindow.onEditEntered(_target, _button, _id)
    if _button.internal ~= "OK" then return end
    COOPTodoState.edit(_id, _button.parent.entry:getText())
end

function COOPTodoWindow:onEdit()
    local entry = self:selectedEntry()
    if entry == nil then return end

    local modal = ISTextBox:new(0, 0, 360, 180, getText("UI_COOP_Todo_EditPrompt"),
            entry.text or "", self, COOPTodoWindow.onEditEntered, 0, entry.id)
    modal:initialise()
    modal:addToUIManager()
end

function COOPTodoWindow:onRemove()
    local entry = self:selectedEntry()
    if entry == nil then return end
    COOPTodoState.remove(entry.id)
end

function COOPTodoWindow.onClearConfirm(_target, _button)
    if _button.internal == "YES" then
        COOPTodoState.clearDone()
    end
end

function COOPTodoWindow:onClearDone()
    local modal = ISModalDialog:new(0, 0, 320, 120, getText("UI_COOP_Todo_ClearConfirm"), true,
            self, COOPTodoWindow.onClearConfirm, 0)
    modal:initialise()
    modal:addToUIManager()
end

function COOPTodoWindow:refreshList()
    local previous = nil
    local selected = self:selectedEntry()
    if selected ~= nil then previous = selected.id end

    self.list:clear()
    self.list:setScrollHeight(0)

    for _, entry in ipairs(COOPTodoState.getSorted()) do
        local done = COOPTodo.isDone(entry)
        local keep = (self.filter == "all")
                or (self.filter == "open" and not done)
                or (self.filter == "done" and done)
        if keep then
            local row = self.list:addItem(entry.text or "", entry)
            row.height = ROW_HGT
            if entry.id == previous then
                self.list.selected = row.itemindex
            end
        end
    end
end

function COOPTodoWindow:prerender()
    ISCollapsableWindow.prerender(self)

    local text
    if not COOPTodoState.isSynced() then
        text = getText("UI_COOP_Todo_Syncing")
    else
        local open, done = COOPTodoState.counts()
        text = getText("UI_COOP_Todo_Counter", tostring(open), tostring(done))
    end
    self:drawText(text, UI_BORDER_SPACING, self.list:getBottom() + 4, 0.8, 0.8, 0.8, 1, UIFont.Small)
end

function COOPTodoWindow:update()
    ISCollapsableWindow.update(self)
    if self.rev ~= COOPTodoState.rev then
        self.rev = COOPTodoState.rev
        self:refreshList()
    end
end

function COOPTodoWindow:onResize()
    ISCollapsableWindow.onResize(self)

    local by = self.height - UI_BORDER_SPACING - BUTTON_HGT
    self.newEntry:setWidth(self.width - UI_BORDER_SPACING * 2 - self.btnAdd:getWidth() - 4)
    self.btnAdd:setX(self.newEntry:getRight() + 4)

    self.list:setWidth(self.width - UI_BORDER_SPACING * 2)
    self.list:setHeight(by - UI_BORDER_SPACING - FONT_HGT_SMALL - 4 - self.list:getY())

    self.btnToggle:setY(by)
    self.btnEdit:setY(by)
    self.btnRemove:setY(by)
    self.btnClear:setY(by)
    self.btnClear:setX(self.width - UI_BORDER_SPACING - self.btnClear:getWidth())
end

-- ESC closes, and is swallowed so it does not also open the main menu.
function COOPTodoWindow:isKeyConsumed(_key)
    return _key == Keyboard.KEY_ESCAPE
end

function COOPTodoWindow:onKeyRelease(_key)
    if _key == Keyboard.KEY_ESCAPE and self:getIsVisible() then
        self:close()
    end
end

function COOPTodoWindow:close()
    self:setVisible(false)
    self:removeFromUIManager()
end

function COOPTodoWindow:new(_x, _y, _width, _height)
    local o = ISCollapsableWindow:new(_x, _y, _width, _height)
    setmetatable(o, self)
    self.__index = self
    o.title = getText("UI_COOP_Todo_Title")
    o.filter = "all"
    o.rev = -1
    o:setResizable(true)
    return o
end

-- A window from the previous session belongs to a Lua state that is gone.
Events.OnGameStart.Add(function()
    local window = COOPTodoWindow.instance
    if window ~= nil then
        window:removeFromUIManager()
        COOPTodoWindow.instance = nil
    end
end)

function COOPTodoWindow.toggle()
    if not COOP.featureEnabled(COOP.F_TODO) then return end

    local window = COOPTodoWindow.instance
    if window ~= nil and window:getIsVisible() then
        window:close()
        return
    end

    if window == nil then
        local width = 520
        local height = 420
        window = COOPTodoWindow:new((getCore():getScreenWidth() - width) / 2,
                (getCore():getScreenHeight() - height) / 2, width, height)
        window:initialise()
        window:instantiate()
        COOPTodoWindow.instance = window
    end

    window:setVisible(true)
    window:addToUIManager()
    window:refreshList()
end
