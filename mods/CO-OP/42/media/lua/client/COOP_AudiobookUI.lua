--
-- CO-OP - audiobooks: the computer's menu, the two actions at it, and what the player is
-- told about their listening.
--
-- Right-clicking a desktop computer offers "Computer" with two submenus, one entry per
-- item the player carries: burn a skill book onto a blank disc, or wipe a CD back to
-- blank. Without power the entries are there but greyed out, with the reason.
--
-- The actions only sit at the computer for the time it takes; the discs are made and
-- destroyed by the server (COOP_AudiobookServer), which checks the computer, its power
-- and the items again. Like the clay dig, the actions have no `complete` on purpose: a
-- timed action that defines one is rebuilt on the server and run on both sides.
--
-- One more client job: a CD player held in the hands plays on its holder's client only,
-- so in multiplayer the lines it plays are reported to the server from here.
--

if isServer() then return end

require "COOP_Audiobook"
require "TimedActions/ISBaseTimedAction"

COOPAudiobookUI = COOPAudiobookUI or {}

local function bookName(_fullType)
    local book = COOPAudiobook.bookForType(_fullType)
    if book ~= nil then return getText(book.nameKey) end
    return tostring(_fullType)
end

-- ---------------------------------------------------------------------------
-- what the player is told
-- ---------------------------------------------------------------------------

-- Pages heard of a book. The server has already set them on its copy of the player;
-- this is the client's copy, which is the one the book's tooltip reads.
function COOPAudiobookUI.onPages(_player, _fullType, _pages, _done)
    if _player == nil then return end
    pcall(function() _player:setAlreadyReadPages(_fullType, _pages) end)
    if _done then
        pcall(function()
            HaloTextHelper.addGoodText(_player, getText("IGUI_COOP_Audiobook_Done", bookName(_fullType)))
        end)
    end
end

function COOPAudiobookUI.onWrongLevel(_player, _fullType)
    if _player == nil then return end
    pcall(function()
        HaloTextHelper.addBadText(_player, getText("IGUI_COOP_Audiobook_WrongLevel"))
    end)
end

function COOPAudiobookUI.report(_what, _name, _reason)
    if _name ~= nil then
        if _what == "burn" then
            COOP.sayInChat(getText("UI_COOP_Audiobook_Burned", _name))
        else
            COOP.sayInChat(getText("UI_COOP_Audiobook_Erased"))
        end
        return
    end
    if _reason == "power" then
        COOP.sayInChat(getText("UI_COOP_Audiobook_NoPower"))
    elseif _reason ~= nil and _reason ~= "off" then
        COOP.sayInChat(getText("UI_COOP_Audiobook_Failed"))
    end
end

local function onServerCommand(_module, _command, _args)
    if _module ~= COOPAudiobook.MODULE or _args == nil then return end
    if _command == COOPAudiobook.CMD_PAGES then
        local player = getPlayer()
        if _args.wrongLevel then
            COOPAudiobookUI.onWrongLevel(player, _args.book)
        else
            COOPAudiobookUI.onPages(player, _args.book, tonumber(_args.pages) or 0, _args.done == true)
        end
    elseif _command == COOPAudiobook.CMD_RESULT then
        COOPAudiobookUI.report(_args.what, _args.name, _args.reason)
    end
end

Events.OnServerCommand.Add(onServerCommand)

-- A held CD player in multiplayer. Radio.AddDeviceText fires the event with -1 for the
-- square and itself as the device, on its holder's client only. World and car radios
-- are the server's business, so their lines are left alone here.
local function onDeviceText(_guid, _codes, _x, _y, _z, _line, _device)
    if not isClient() then return end
    if _codes ~= COOPAudiobook.CODES then return end
    if not (_x == -1 and _y == -1 and _z == -1) then return end
    if not COOPAudiobook.isEnabled() then return end

    local ok, id, holder = pcall(function()
        local media = _device:getDeviceData():getMediaData()
        return media and media:getId() or nil, _device:getPlayer()
    end)
    if not ok or id == nil or holder == nil or not holder:isLocalPlayer() then return end
    if COOPAudiobook.bookForMediaId(id) == nil then return end

    sendClientCommand(holder, COOPAudiobook.MODULE, COOPAudiobook.CMD_HEARD, { media = id })
end

Events.OnDeviceText.Add(onDeviceText)

-- ---------------------------------------------------------------------------
-- the action at the computer
--
-- One class for both jobs: _job is "burn" (items = { book, blank }) or "erase"
-- (items = { disc }).
-- ---------------------------------------------------------------------------

COOPAudiobookAction = ISBaseTimedAction:derive("COOPAudiobookAction")

function COOPAudiobookAction:isValid()
    if not COOPAudiobook.isEnabled() then return false end
    if self.computer == nil or self.computer:getSquare() == nil then return false end
    if not COOPAudiobook.isPowered(self.computer) then return false end
    local inventory = self.character:getInventory()
    for _, item in ipairs(self.items) do
        if not inventory:containsRecursive(item) then return false end
    end
    return true
end

function COOPAudiobookAction:waitToStart()
    self.character:faceThisObject(self.computer)
    return self.character:shouldBeTurning()
end

function COOPAudiobookAction:update()
    self.character:faceThisObject(self.computer)
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function COOPAudiobookAction:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Mid")
end

function COOPAudiobookAction:stop()
    ISBaseTimedAction.stop(self)
end

function COOPAudiobookAction:perform()
    local square = self.computer:getSquare()
    local args = { x = square:getX(), y = square:getY(), z = square:getZ() }
    local command
    if self.job == "burn" then
        command = COOPAudiobook.CMD_BURN
        args.book = self.items[1]:getID()
        args.blank = self.items[2]:getID()
    else
        command = COOPAudiobook.CMD_ERASE
        args.disc = self.items[1]:getID()
    end

    if isClient() then
        sendClientCommand(self.character, COOPAudiobook.MODULE, command, args)
    elseif COOPAudiobookServer ~= nil then
        -- Single player: one Lua state, so call the authority and answer at once.
        local name, reason
        if self.job == "burn" then
            name, reason = COOPAudiobookServer.burn(self.character, args)
        else
            name, reason = COOPAudiobookServer.erase(self.character, args)
        end
        COOPAudiobookUI.report(self.job, name, reason)
    end

    ISBaseTimedAction.perform(self)
end

function COOPAudiobookAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    local minutes = self.job == "burn" and COOPAudiobook.BURN_MINUTES or COOPAudiobook.ERASE_MINUTES
    return COOPAudiobook.ticksFor(minutes)
end

function COOPAudiobookAction:new(character, computer, job, items)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.computer = computer
    o.job = job
    o.items = items
    o.maxTime = o:getDuration()
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

local function queue(_player, _computer, _job, _items)
    for _, item in ipairs(_items) do
        ISInventoryPaneContextMenu.transferIfNeeded(_player, item)
    end
    if not luautils.walkAdj(_player, _computer:getSquare(), true) then return end
    ISTimedActionQueue.add(COOPAudiobookAction:new(_player, _computer, _job, _items))
end

local function onBurn(_player, _computer, _book, _blank)
    queue(_player, _computer, "burn", { _book, _blank })
end

local function onErase(_player, _computer, _disc)
    queue(_player, _computer, "erase", { _disc })
end

-- One entry per distinct thing: three copies of the same book burn the same audiobook,
-- so listing them three times says nothing.
local function distinct(_items, _keyOf)
    local seen, out = {}, {}
    for _, item in ipairs(_items) do
        local key = _keyOf(item)
        if not seen[key] then
            seen[key] = true
            table.insert(out, item)
        end
    end
    table.sort(out, function(a, b) return a:getDisplayName() < b:getDisplayName() end)
    return out
end

local function onFillWorldObjectContextMenu(_playerNum, _context, _worldobjects, _test)
    if _test and ISWorldObjectContextMenu.Test then return true end
    if not COOPAudiobook.isEnabled() then return end

    local player = getSpecificPlayer(_playerNum)
    if player == nil or player:getVehicle() ~= nil then return end

    local computer = nil
    for _, object in ipairs(_worldobjects) do
        computer = COOPAudiobook.findComputer(object:getSquare())
        if computer ~= nil then break end
    end
    if computer == nil then return end
    if _test then return ISWorldObjectContextMenu.setTest() end

    local root = _context:addOption(getText("ContextMenu_COOP_Computer"), nil, nil)
    local menu = ISContextMenu:getNew(_context)
    _context:addSubMenu(root, menu)

    local powered = COOPAudiobook.isPowered(computer)

    -- burn
    local books = distinct(COOPAudiobook.collect(player, function(item)
        return COOPAudiobook.bookForItem(item) ~= nil
    end), function(item) return item:getFullType() end)
    local blanks = COOPAudiobook.collect(player, COOPAudiobook.isBlank)

    local burn = menu:addOption(getText("ContextMenu_COOP_Audiobook_Burn"), nil, nil)
    if not powered then
        disable(burn, getText("ContextMenu_COOP_Computer_NoPower"))
    elseif #books == 0 then
        disable(burn, getText("ContextMenu_COOP_Audiobook_NoBook"))
    elseif #blanks == 0 then
        disable(burn, getText("ContextMenu_COOP_Audiobook_NoBlank"))
    else
        local sub = ISContextMenu:getNew(menu)
        menu:addSubMenu(burn, sub)
        for _, book in ipairs(books) do
            local option = sub:addOption(book:getDisplayName(), player, onBurn, computer, book, blanks[1])
            option.iconTexture = book:getTex()
        end
    end

    -- erase
    local discs = distinct(COOPAudiobook.collect(player, COOPAudiobook.isErasable),
            function(item) return item:getDisplayName() end)

    local erase = menu:addOption(getText("ContextMenu_COOP_Audiobook_Erase"), nil, nil)
    if not powered then
        disable(erase, getText("ContextMenu_COOP_Computer_NoPower"))
    elseif #discs == 0 then
        disable(erase, getText("ContextMenu_COOP_Audiobook_NoDisc"))
    else
        local sub = ISContextMenu:getNew(menu)
        menu:addSubMenu(erase, sub)
        for _, disc in ipairs(discs) do
            local option = sub:addOption(disc:getDisplayName(), player, onErase, computer, disc)
            option.iconTexture = disc:getTex()
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
