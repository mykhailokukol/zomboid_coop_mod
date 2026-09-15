--
-- CO-OP - shared map marks.
--
-- The game can already share map annotations, but one at a time: draw a symbol, open
-- the Sharing dialog, pick "everyone". This adds an "MP" tick box under that button.
-- While it is on - and it is on by default - every symbol and note the player draws is
-- shared with the whole server the moment it is placed.
--
-- It rides on the vanilla sharing API (WorldMapSymbolsV2), so the marks travel through
-- the game's own network path and obey its rules: only the author can change a mark,
-- and other players see it live.
--

if isServer() then return end

require "COOP_Common"

COOPMapShare = COOPMapShare or {}

local MODDATA_KEY = "COOP_ShareMapMarks"
local UI_BORDER_SPACING = 10
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BUTTON_HGT = FONT_HGT_SMALL + 6

local patched = false

-- On by default; the choice is remembered per character.
function COOPMapShare.isEnabled()
    if not COOP.featureEnabled(COOP.F_MAPSHARE) then return false end

    local player = getPlayer()
    if player == nil then return true end
    local stored = player:getModData()[MODDATA_KEY]
    if stored == nil then return true end
    return stored == true
end

function COOPMapShare.setEnabled(_enabled)
    local player = getPlayer()
    if player == nil then return end
    player:getModData()[MODDATA_KEY] = _enabled == true
    COOP.log("map marks are now " .. (_enabled and "shared with everyone" or "private"))
end

local function symbolCount(_symbolsAPI)
    if _symbolsAPI == nil then return nil end
    local ok, count = pcall(function() return _symbolsAPI:getSymbolCount() end)
    if ok then return count end
    return nil
end

local function shareSymbol(_symbol)
    if _symbol == nil then return end
    local ok, err = pcall(function()
        if not _symbol:canClientModify() then return end
        if _symbol:isShared() then return end
        _symbol:setSharing({ everyone = true })
    end)
    if not ok then
        COOP.log("could not share a map mark: " .. tostring(err))
    end
end

-- Symbols are appended to the list, so everything past the count taken before the tool
-- ran is what the player just drew.
local function shareSymbolsAddedSince(_symbolsAPI, _previousCount)
    if _symbolsAPI == nil or _previousCount == nil then return end
    if not COOPMapShare.isEnabled() then return end

    local count = symbolCount(_symbolsAPI)
    if count == nil then return end

    for i = _previousCount, count - 1 do
        local ok, symbol = pcall(function() return _symbolsAPI:getSymbolByIndex(i) end)
        if ok then shareSymbol(symbol) end
    end
end

local function patch()
    if patched then return end
    if ISWorldMapSymbols == nil or ISWorldMapSymbolTool_AddSymbol == nil
            or ISWorldMapSymbolTool_AddNote == nil then
        return
    end
    patched = true

    -- ---- the tick box, under the vanilla Sharing button -------------------
    local originalCreateChildren = ISWorldMapSymbols.createChildren

    function ISWorldMapSymbols:createChildren()
        originalCreateChildren(self)

        -- Same condition as the vanilla Sharing button: nothing to share in solo play.
        if not isClient() then return end
        if not COOP.featureEnabled(COOP.F_MAPSHARE) then return end

        local anchor = self.sharingBtn or self.removeBtn
        if anchor == nil then return end

        local label = getText("UI_COOP_MapShareMP")
        local width = getTextManager():MeasureStringX(UIFont.Small, label) + 30
        local tickBox = ISTickBox:new(UI_BORDER_SPACING + 1, anchor:getBottom() + UI_BORDER_SPACING,
                width, BUTTON_HGT, "", self, ISWorldMapSymbols.onCoopShareTicked)
        tickBox:initialise()
        tickBox:instantiate()
        tickBox:addOption(label)
        tickBox.tooltip = getText("UI_COOP_MapShareMP_tt")
        tickBox:setSelected(1, COOPMapShare.isEnabled())
        self:addChild(tickBox)
        self.coopShareTickBox = tickBox

        -- keeps joypad navigation working; harmless if the helper ever changes
        pcall(function() self:insertNewLineOfButtons(tickBox) end)

        self:setHeight(tickBox:getBottom() + UI_BORDER_SPACING + 1)
    end

    function ISWorldMapSymbols:onCoopShareTicked(_index, _selected)
        COOPMapShare.setEnabled(_selected == true)
    end

    -- ---- share whatever the drawing tools create ---------------------------
    local originalAddSymbol = ISWorldMapSymbolTool_AddSymbol.addSymbol

    function ISWorldMapSymbolTool_AddSymbol:addSymbol(_x, _y)
        local before = symbolCount(self.symbolsAPI)
        originalAddSymbol(self, _x, _y)
        shareSymbolsAddedSince(self.symbolsAPI, before)
    end

    local originalNoteAdded = ISWorldMapSymbolTool_AddNote.onNoteAdded

    function ISWorldMapSymbolTool_AddNote:onNoteAdded(_button, _playerNum)
        local before = symbolCount(self.symbolsAPI)
        originalNoteAdded(self, _button, _playerNum)
        shareSymbolsAddedSince(self.symbolsAPI, before)
    end

    COOP.log("map mark sharing ready")
end

patch()
Events.OnGameBoot.Add(patch)
