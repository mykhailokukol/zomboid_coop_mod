--
-- CO-OP / Books at home - the shared checklist window.
--

if isServer() then return end

require "ISUI/ISCollapsableWindow"
require "BAH_Common"
require "BAH_Catalog"

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local UI_BORDER_SPACING = 10
local BUTTON_HGT = FONT_HGT_SMALL + 6
local ROW_HGT = FONT_HGT_SMALL * 2 + 10
local ICON_SIZE = 22

local COLOR_HOME = { r = 0.45, g = 0.85, b = 0.45 }
local COLOR_MISSING = { r = 0.65, g = 0.65, b = 0.65 }
local COLOR_DIM = { r = 0.62, g = 0.62, b = 0.62 }

BooksAtHomeWindow = ISCollapsableWindow:derive("BooksAtHomeWindow")
BooksAtHomeWindow.instance = nil

-- --------------------------------------------------------------------------
-- list rendering
-- --------------------------------------------------------------------------

local function drawRow(self, y, item, alt)
    if item.height == nil then item.height = ROW_HGT end
    if (y + self:getYScroll() + item.height < 0) or (y + self:getYScroll() >= self.height) then
        return y + item.height
    end

    local entry = item.item.catalog
    local mark = item.item.mark
    local width = self:getWidth()

    if self.selected == item.index then
        self:drawRect(0, y, width, item.height - 1, 0.25, 0.6, 0.5, 0.25)
    elseif self.mouseoverselected == item.index and self:isMouseOver() and not self:isMouseOverScrollBar() then
        self:drawRect(0, y, width, item.height - 1, 0.12, 1, 1, 1)
    end
    self:drawRectBorder(0, y, width, item.height, 0.35, self.borderColor.r, self.borderColor.g, self.borderColor.b)

    if entry.texture ~= nil then
        self:drawTextureScaledAspect(entry.texture, 5, y + (item.height - ICON_SIZE) / 2, ICON_SIZE, ICON_SIZE, 1, 1, 1, 1)
    end

    local textX = 5 + ICON_SIZE + 6
    local line1 = y + 4
    local line2 = line1 + FONT_HGT_SMALL

    self:drawText(entry.name, textX, line1, 1, 1, 1, 1, UIFont.Small)
    self:drawText(BAH.catalogSubtitle(entry), textX, line2, COLOR_DIM.r, COLOR_DIM.g, COLOR_DIM.b, 1, UIFont.Small)

    if mark ~= nil then
        local status = getText("UI_BooksAtHome_StatusHome")
        self:drawTextRight(status, width - 10, line1, COLOR_HOME.r, COLOR_HOME.g, COLOR_HOME.b, 1, UIFont.Small)

        local detail = (mark.by or "?")
        if mark.when then detail = detail .. " - " .. mark.when end
        if mark.note then detail = detail .. " - " .. mark.note end
        self:drawTextRight(detail, width - 10, line2, COLOR_DIM.r, COLOR_DIM.g, COLOR_DIM.b, 1, UIFont.Small)
    else
        self:drawTextRight(getText("UI_BooksAtHome_StatusMissing"), width - 10, line1,
                COLOR_MISSING.r, COLOR_MISSING.g, COLOR_MISSING.b, 1, UIFont.Small)
    end

    return y + item.height
end

-- --------------------------------------------------------------------------
-- window
-- --------------------------------------------------------------------------

function BooksAtHomeWindow:createChildren()
    ISCollapsableWindow.createChildren(self)

    local th = self:titleBarHeight()
    local x = UI_BORDER_SPACING
    local y = th + UI_BORDER_SPACING

    self.searchEntry = ISTextEntryBox:new("", x, y, 180, BUTTON_HGT)
    self.searchEntry:initialise()
    self.searchEntry:instantiate()
    self.searchEntry.onTextChange = function() self:refreshList() end
    self:addChild(self.searchEntry)

    -- row 1: what kind of literature
    local bx = self.searchEntry:getRight() + UI_BORDER_SPACING
    self.btnAll = self:addFilterButton(bx, y, getText("UI_BooksAtHome_FilterAll"), "all", BooksAtHomeWindow.onTypeButton)
    self.btnBooks = self:addFilterButton(self.btnAll:getRight() + 4, y, getText("UI_BooksAtHome_FilterBooks"), "book", BooksAtHomeWindow.onTypeButton)
    self.btnMags = self:addFilterButton(self.btnBooks:getRight() + 4, y, getText("UI_BooksAtHome_FilterMagazines"), "magazine", BooksAtHomeWindow.onTypeButton)
    self.btnMedia = self:addFilterButton(self.btnMags:getRight() + 4, y, getText("UI_BooksAtHome_FilterMedia"), "media", BooksAtHomeWindow.onTypeButton)

    -- row 2: marked / not marked
    local y2 = y + BUTTON_HGT + 6
    self.statusLabelX = x
    local sx = x + getTextManager():MeasureStringX(UIFont.Small, getText("UI_BooksAtHome_ShowLabel")) + 8
    self.btnStatusAny = self:addFilterButton(sx, y2, getText("UI_BooksAtHome_FilterAll"), "any", BooksAtHomeWindow.onStatusButton)
    self.btnStatusHome = self:addFilterButton(self.btnStatusAny:getRight() + 4, y2, getText("UI_BooksAtHome_FilterAtHome"), "home", BooksAtHomeWindow.onStatusButton)
    self.btnStatusMissing = self:addFilterButton(self.btnStatusHome:getRight() + 4, y2, getText("UI_BooksAtHome_FilterMissing"), "missing", BooksAtHomeWindow.onStatusButton)
    self.statusLabelY = y2 + (BUTTON_HGT - FONT_HGT_SMALL) / 2

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
    self.btnMark = self:addActionButton(x, by, getText("UI_BooksAtHome_Mark"), self.onMark)
    self.btnUnmark = self:addActionButton(self.btnMark:getRight() + 4, by, getText("UI_BooksAtHome_Unmark"), self.onUnmark)
    self.btnNote = self:addActionButton(self.btnUnmark:getRight() + 4, by, getText("UI_BooksAtHome_EditNote"), self.onEditNote)

    local resetLabel = getText("UI_BooksAtHome_ClearAll")
    local resetWidth = getTextManager():MeasureStringX(UIFont.Small, resetLabel) + 20
    self.btnReset = ISButton:new(self.width - UI_BORDER_SPACING - resetWidth, by, resetWidth, BUTTON_HGT,
            resetLabel, self, BooksAtHomeWindow.onReset)
    self.btnReset:initialise()
    self.btnReset:instantiate()
    self.btnReset:enableCancelColor()
    self:addChild(self.btnReset)

    self:setFilter("all")
    self:setStatusFilter("any")
    self:refreshList()
end

function BooksAtHomeWindow:addFilterButton(_x, _y, _text, _filter, _onclick)
    local width = getTextManager():MeasureStringX(UIFont.Small, _text) + 20
    local btn = ISButton:new(_x, _y, width, BUTTON_HGT, _text, self, _onclick)
    btn.internal = _filter
    btn:initialise()
    btn:instantiate()
    self:addChild(btn)
    return btn
end

function BooksAtHomeWindow:addActionButton(_x, _y, _text, _onclick)
    local width = getTextManager():MeasureStringX(UIFont.Small, _text) + 20
    local btn = ISButton:new(_x, _y, width, BUTTON_HGT, _text, self, _onclick)
    btn:initialise()
    btn:instantiate()
    self:addChild(btn)
    return btn
end

local function highlight(_buttons, _selected)
    for name, btn in pairs(_buttons) do
        if btn ~= nil then
            btn.backgroundColor.a = (name == _selected) and 0.9 or 0.4
        end
    end
end

function BooksAtHomeWindow:setFilter(_filter)
    self.filter = _filter
    -- keys match the catalog "kind" values so refreshList can compare directly
    highlight({ all = self.btnAll, book = self.btnBooks, magazine = self.btnMags,
                media = self.btnMedia }, _filter)
end

function BooksAtHomeWindow:setStatusFilter(_status)
    self.status = _status
    highlight({ any = self.btnStatusAny, home = self.btnStatusHome, missing = self.btnStatusMissing }, _status)
end

function BooksAtHomeWindow:onTypeButton(_button)
    self:setFilter(_button.internal)
    self:refreshList()
end

function BooksAtHomeWindow:onStatusButton(_button)
    self:setStatusFilter(_button.internal)
    self:refreshList()
end

function BooksAtHomeWindow:selectedEntry()
    local item = self.list.items[self.list.selected]
    if item == nil then return nil end
    return item.item.catalog
end

function BooksAtHomeWindow:onMark()
    local entry = self:selectedEntry()
    if entry == nil then return end
    BooksAtHome.mark(entry.key, nil)
end

function BooksAtHomeWindow:onUnmark()
    local entry = self:selectedEntry()
    if entry == nil then return end
    BooksAtHome.unmark(entry.key)
end

function BooksAtHomeWindow:onDoubleClick()
    local entry = self:selectedEntry()
    if entry == nil then return end
    BooksAtHome.toggle(entry.key, nil)
end

function BooksAtHomeWindow.onNoteEntered(_target, _button, _key)
    if _button.internal ~= "OK" then return end
    BooksAtHome.setNote(_key, _button.parent.entry:getText())
end

function BooksAtHomeWindow:onEditNote()
    local entry = self:selectedEntry()
    if entry == nil then return end
    local mark = BooksAtHome.getEntry(entry.key)
    local modal = ISTextBox:new(0, 0, 320, 180,
            getText("UI_BooksAtHome_NotePrompt", entry.name),
            (mark ~= nil and mark.note) or "", self, BooksAtHomeWindow.onNoteEntered, 0, entry.key)
    modal:initialise()
    modal:addToUIManager()
end

function BooksAtHomeWindow.onResetConfirm(_target, _button)
    if _button.internal == "YES" then
        BooksAtHome.reset()
    end
end

function BooksAtHomeWindow:onReset()
    local modal = ISModalDialog:new(0, 0, 300, 120, getText("UI_BooksAtHome_ClearConfirm"), true,
            self, BooksAtHomeWindow.onResetConfirm, 0)
    modal:initialise()
    modal:addToUIManager()
end

function BooksAtHomeWindow:refreshList()
    local previous = nil
    local selectedItem = self.list.items[self.list.selected]
    if selectedItem ~= nil then previous = selectedItem.item.catalog.key end

    self.list:clear()
    self.list:setScrollHeight(0)

    local search = string.lower(self.searchEntry:getInternalText() or "")
    local marked, total = 0, 0

    for _, entry in ipairs(BAH.getCatalogOrder()) do
        local mark = BooksAtHome.getEntry(entry.key)
        total = total + 1
        if mark ~= nil then marked = marked + 1 end

        local show = true
        if self.filter ~= "all" and entry.kind ~= self.filter then show = false end
        if self.status == "home" and mark == nil then show = false end
        if self.status == "missing" and mark ~= nil then show = false end

        if show and search ~= "" then
            local haystack = string.lower(entry.name .. " " .. (entry.skillName or "") .. " "
                    .. (entry.category or "") .. " " .. BAH.catalogSubtitle(entry) .. " "
                    .. ((mark and mark.note) or "") .. " " .. ((mark and mark.by) or ""))
            show = string.find(haystack, search, 1, true) ~= nil
        end

        if show then
            local row = self.list:addItem(entry.name, { catalog = entry, mark = mark })
            row.height = ROW_HGT
            if entry.key == previous then
                self.list.selected = row.itemindex
            end
        end
    end

    self.markedCount = marked
    self.totalCount = total
    self.btnReset:setVisible(BooksAtHome.canReset())
end

function BooksAtHomeWindow:prerender()
    ISCollapsableWindow.prerender(self)

    self:drawText(getText("UI_BooksAtHome_ShowLabel"), self.statusLabelX or UI_BORDER_SPACING,
            self.statusLabelY or 0, 0.8, 0.8, 0.8, 1, UIFont.Small)

    local text
    if not BooksAtHome.isSynced() then
        text = getText("UI_BooksAtHome_Syncing")
    else
        text = getText("UI_BooksAtHome_Counter", tostring(self.markedCount or 0), tostring(self.totalCount or 0))
    end
    self:drawText(text, UI_BORDER_SPACING, self.list:getBottom() + 4, 0.8, 0.8, 0.8, 1, UIFont.Small)
end

function BooksAtHomeWindow:update()
    ISCollapsableWindow.update(self)
    if self.rev ~= BooksAtHome.rev then
        self.rev = BooksAtHome.rev
        self:refreshList()
    end
end

function BooksAtHomeWindow:onResize()
    ISCollapsableWindow.onResize(self)

    local listY = self.list:getY()
    local by = self.height - UI_BORDER_SPACING - BUTTON_HGT
    self.list:setWidth(self.width - UI_BORDER_SPACING * 2)
    self.list:setHeight(by - UI_BORDER_SPACING - FONT_HGT_SMALL - 4 - listY)
    self.btnMark:setY(by)
    self.btnUnmark:setY(by)
    self.btnNote:setY(by)
    self.btnReset:setY(by)
    self.btnReset:setX(self.width - UI_BORDER_SPACING - self.btnReset:getWidth())
end

function BooksAtHomeWindow:isKeyConsumed(_key)
    return _key == Keyboard.KEY_ESCAPE
end

function BooksAtHomeWindow:onKeyRelease(_key)
    if _key == Keyboard.KEY_ESCAPE and self:getIsVisible() then
        self:close()
    end
end

function BooksAtHomeWindow:close()
    self:setVisible(false)
    self:removeFromUIManager()
end

function BooksAtHomeWindow:new(_x, _y, _width, _height)
    local o = ISCollapsableWindow:new(_x, _y, _width, _height)
    setmetatable(o, self)
    self.__index = self
    o.title = getText("UI_BooksAtHome_Title")
    o.filter = "all"
    o.status = "any"
    o.rev = -1
    o.markedCount = 0
    o.totalCount = 0
    o:setResizable(true)
    return o
end

Events.OnGameStart.Add(function()
    local window = BooksAtHomeWindow.instance
    if window ~= nil then
        window:removeFromUIManager()
        BooksAtHomeWindow.instance = nil
    end
end)

function BooksAtHomeWindow.toggle()
    if not COOP.featureEnabled(COOP.F_BOOKS) then return end

    local window = BooksAtHomeWindow.instance
    if window ~= nil and window:getIsVisible() then
        window:close()
        return
    end
    if window == nil then
        local width = 780
        local height = 460
        window = BooksAtHomeWindow:new((getCore():getScreenWidth() - width) / 2,
                (getCore():getScreenHeight() - height) / 2, width, height)
        window:initialise()
        window:instantiate()
        BooksAtHomeWindow.instance = window
    end
    window:setVisible(true)
    window:addToUIManager()
    window:refreshList()
end
