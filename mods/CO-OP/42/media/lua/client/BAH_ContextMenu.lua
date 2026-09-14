--
-- CO-OP / Books at home - inventory right-click options.
--

if isServer() then return end

require "BAH_Common"
require "BAH_Catalog"

BooksAtHomeContextMenu = {}

-- Unique tracking keys for the clicked selection (books by item type, tapes by recording).
local function collectKeys(_items)
    local seen = {}
    local keys = {}
    for _, v in ipairs(_items) do
        local item = v
        if not instanceof(v, "InventoryItem") then
            item = v.items and v.items[1] or nil
        end
        local key = BAH.keyForItem(item)
        if key ~= nil and not seen[key] then
            seen[key] = true
            table.insert(keys, key)
        end
    end
    return keys
end

function BooksAtHomeContextMenu.onMark(_keys)
    for _, key in ipairs(_keys) do
        BooksAtHome.mark(key, nil)
    end
end

function BooksAtHomeContextMenu.onUnmark(_keys)
    for _, key in ipairs(_keys) do
        BooksAtHome.unmark(key)
    end
end

function BooksAtHomeContextMenu.onNoteEntered(_target, _button, _key)
    if _button.internal ~= "OK" then return end
    BooksAtHome.setNote(_key, _button.parent.entry:getText())
end

function BooksAtHomeContextMenu.onEditNote(_key, _playerNum)
    local entry = BAH.getCatalogEntry(_key)
    local mark = BooksAtHome.getEntry(_key)
    local modal = ISTextBox:new(0, 0, 320, 180,
            getText("UI_BooksAtHome_NotePrompt", entry and entry.name or _key),
            (mark ~= nil and mark.note) or "",
            BooksAtHomeContextMenu, BooksAtHomeContextMenu.onNoteEntered, _playerNum, _key)
    modal:initialise()
    modal:addToUIManager()
end

function BooksAtHomeContextMenu.onOpenList()
    BooksAtHomeWindow.toggle()
end

local function onFillInventoryObjectContextMenu(_playerNum, _context, _items)
    local keys = collectKeys(_items)
    if #keys == 0 then return end

    local parent = _context:addOption(getText("ContextMenu_BooksAtHome"))
    local submenu = ISContextMenu:getNew(_context)
    _context:addSubMenu(parent, submenu)

    if #keys == 1 then
        local key = keys[1]
        if BooksAtHome.isMarked(key) then
            submenu:addOption(getText("ContextMenu_BooksAtHome_Unmark"), keys, BooksAtHomeContextMenu.onUnmark)
        else
            submenu:addOption(getText("ContextMenu_BooksAtHome_Mark"), keys, BooksAtHomeContextMenu.onMark)
        end
        submenu:addOption(getText("ContextMenu_BooksAtHome_EditNote"), key, BooksAtHomeContextMenu.onEditNote, _playerNum)

        local mark = BooksAtHome.getEntry(key)
        if mark ~= nil then
            local tooltip = ISWorldObjectContextMenu.addToolTip()
            tooltip.description = getText("UI_BooksAtHome_TooltipMarked", mark.by or "?", mark.when or "?")
            if mark.note then
                tooltip.description = tooltip.description .. " <LINE> " .. mark.note
            end
            parent.toolTip = tooltip
        end
    else
        submenu:addOption(getText("ContextMenu_BooksAtHome_MarkAll", tostring(#keys)), keys, BooksAtHomeContextMenu.onMark)
        submenu:addOption(getText("ContextMenu_BooksAtHome_UnmarkAll", tostring(#keys)), keys, BooksAtHomeContextMenu.onUnmark)
    end

    submenu:addOption(getText("ContextMenu_BooksAtHome_OpenList"), nil, BooksAtHomeContextMenu.onOpenList)
end

Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)
