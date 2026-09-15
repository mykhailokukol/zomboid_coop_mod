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

-- ---------------------------------------------------------------------------
-- right-clicking a container in the world
--
-- The point is to clear a bookcase in one go instead of selecting its contents first.
-- ---------------------------------------------------------------------------

-- How close the player has to be. The loot window reaches two tiles, so this is what
-- "I can see what is in there" means - and in multiplayer it is also roughly how far
-- container contents have actually been sent to this client.
local CONTAINER_REACH = 3

-- Walks a container and anything packed inside it. The depth cap is for a bag in a bag
-- in a bag; three is already more nesting than the game usually produces.
local function collectFromContainer(_container, _seen, _keys, _depth)
    if _container == nil or _depth > 3 then return end

    local items = _container:getItems()
    if items == nil then return end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item ~= nil then
            local key = BAH.keyForItem(item)
            if key ~= nil and not _seen[key] then
                _seen[key] = true
                table.insert(_keys, key)
            end
            if instanceof(item, "InventoryContainer") then
                collectFromContainer(item:getInventory(), _seen, _keys, _depth + 1)
            end
        end
    end
end

-- Every container on the squares that were clicked, not just on the object the picker
-- chose: a shelf and the crate beside it share a square often enough to matter.
local function collectFromWorld(_playerObj, _worldObjects)
    local seen = {}
    local keys = {}
    local squares = {}

    for _, object in ipairs(_worldObjects) do
        local square = object:getSquare()
        if square ~= nil and not squares[square] then
            squares[square] = true

            if _playerObj:DistToSquared(square:getX() + 0.5, square:getY() + 0.5)
                    <= CONTAINER_REACH * CONTAINER_REACH then
                local objects = square:getObjects()
                if objects ~= nil then
                    for i = 0, objects:size() - 1 do
                        local other = objects:get(i)
                        if other ~= nil then
                            for j = 0, other:getContainerCount() - 1 do
                                collectFromContainer(other:getContainerByIndex(j), seen, keys, 1)
                            end
                        end
                    end
                end
            end
        end
    end

    return keys
end

local function onFillWorldObjectContextMenu(_playerNum, _context, _worldObjects, _test)
    if _test and ISWorldObjectContextMenu.Test then return true end
    if not COOP.featureEnabled(COOP.F_BOOKS) then return end

    local playerObj = getSpecificPlayer(_playerNum)
    if playerObj == nil or playerObj:getVehicle() ~= nil then return end

    local keys = collectFromWorld(playerObj, _worldObjects)
    if #keys == 0 then return end

    local marked, unmarked = {}, {}
    for _, key in ipairs(keys) do
        if BooksAtHome.isMarked(key) then
            table.insert(marked, key)
        else
            table.insert(unmarked, key)
        end
    end

    if _test then return ISWorldObjectContextMenu.setTest() end

    local parent = _context:addOption(getText("ContextMenu_BooksAtHome"))
    local submenu = ISContextMenu:getNew(_context)
    _context:addSubMenu(parent, submenu)

    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip.description = getText("UI_BooksAtHome_ContainerTooltip",
            tostring(#marked), tostring(#keys))
    parent.toolTip = tooltip

    if #unmarked > 0 then
        submenu:addOption(getText("ContextMenu_BooksAtHome_MarkContainer", tostring(#unmarked)),
                unmarked, BooksAtHomeContextMenu.onMark)
    end
    if #marked > 0 then
        submenu:addOption(getText("ContextMenu_BooksAtHome_UnmarkContainer", tostring(#marked)),
                marked, BooksAtHomeContextMenu.onUnmark)
    end

    submenu:addOption(getText("ContextMenu_BooksAtHome_OpenList"), nil, BooksAtHomeContextMenu.onOpenList)
end

local function onFillInventoryObjectContextMenu(_playerNum, _context, _items)
    if not COOP.featureEnabled(COOP.F_BOOKS) then return end

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
Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
