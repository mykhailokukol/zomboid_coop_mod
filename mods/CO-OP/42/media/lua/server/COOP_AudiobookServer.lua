--
-- CO-OP - audiobooks: the authority. Burning and wiping discs, and turning what was
-- heard into pages read.
--
-- Runs on the server, and in single player where there is no server process and the
-- client calls straight in. Both halves have to be here:
--
--   * the discs are items, made and destroyed on the side that owns the inventory;
--   * the XP multiplier can only be set here - the global addXpMultiplier forwards to
--     GameServer.addXpMultiplier on a server, sets it directly with no network at all,
--     and does nothing on a multiplayer client - and the pages are set alongside it so
--     the two cannot disagree.
--
-- Who heard a line: a radio in the world and a car radio play on the server, which fires
-- OnDeviceText with the device's square, and everyone within HEAR_RANGE on that floor,
-- indoors or out the same as the device, awake and not deaf, has heard it - the test
-- vanilla's ISRadioInteractions makes for VHS skill XP. A CD player in someone's hands
-- plays on that player's client only, fires OnDeviceText there with -1 for the square,
-- and the client reports it (CMD_HEARD); it counts for that one player.
--
-- The listening itself is timed by the gaps between lines, see COOP_Audiobook.lua.
--

if isClient() then return end

require "COOP_Audiobook"

COOPAudiobookServer = {}

-- player key -> { [book full type] = { last = game minutes, carry = minutes } }
local listening = {}

-- player key -> { [book full type] = true }, so "wrong volume" is said once a session
local warned = {}

local function nowMinutes()
    return getGameTime():getWorldAgeHours() * 60
end

local function playerKey(_player)
    if isServer() then return COOP.playerName(_player) end
    return "local" .. tostring(_player:getPlayerNum())
end

-- Tell the listener, or in single player show it straight away.
local function notifyPages(_player, _book, _pages, _done)
    if isServer() then
        sendServerCommand(_player, COOPAudiobook.MODULE, COOPAudiobook.CMD_PAGES, {
            book = _book.fullType, pages = _pages, done = _done,
        })
    elseif COOPAudiobookUI ~= nil then
        COOPAudiobookUI.onPages(_player, _book.fullType, _pages, _done)
    end
end

local function notifyLevel(_player, _book)
    local key = playerKey(_player)
    warned[key] = warned[key] or {}
    if warned[key][_book.fullType] then return end
    warned[key][_book.fullType] = true

    if isServer() then
        sendServerCommand(_player, COOPAudiobook.MODULE, COOPAudiobook.CMD_PAGES, {
            book = _book.fullType, wrongLevel = true,
        })
    elseif COOPAudiobookUI ~= nil then
        COOPAudiobookUI.onWrongLevel(_player, _book.fullType)
    end
end

-- ---------------------------------------------------------------------------
-- listening
-- ---------------------------------------------------------------------------

-- One line of _book heard by _player.
function COOPAudiobookServer.heard(_player, _book)
    if _player == nil or _book == nil then return end
    if not COOPAudiobook.isEnabled() then return end

    local key = playerKey(_player)
    local mine = listening[key]
    if mine == nil then mine = {}; listening[key] = mine end
    local state = mine[_book.fullType]
    local now = nowMinutes()

    if state == nil then
        mine[_book.fullType] = { last = now, carry = 0 }
        return
    end

    local gap = now - state.last
    state.last = now
    if gap <= 0 or gap > COOPAudiobook.MAX_GAP_MINUTES then return end

    if not COOPAudiobook.levelSuits(_player, _book) then
        state.carry = 0
        notifyLevel(_player, _book)
        return
    end

    local read = _player:getAlreadyReadPages(_book.fullType)
    if read >= _book.pages then return end

    state.carry = state.carry + gap
    local perPage = COOPAudiobook.minutesPerPage(_player)
    if perPage <= 0 then perPage = 0.01 end
    local add = math.floor(state.carry / perPage)
    if add <= 0 then return end
    state.carry = state.carry - add * perPage

    local pages = math.min(_book.pages, read + add)
    _player:setAlreadyReadPages(_book.fullType, pages)

    local perk = COOPAudiobook.perk(_book)
    if perk ~= nil then
        local multiplier = COOPAudiobook.multiplierFor(_book, pages)
        local current = _player:getXp():getMultiplier(perk)
        if multiplier > current then
            addXpMultiplier(_player, perk, multiplier, _book.minLevel, _book.maxLevel)
        end
    end

    local done = pages >= _book.pages
    if done then state.carry = 0 end
    notifyPages(_player, _book, pages, done)

    if COOPAudiobook.debug then
        COOP.log("audiobook: " .. COOP.playerName(_player) .. " " .. _book.fullType
                .. " " .. pages .. "/" .. _book.pages)
    end
end

local function canHear(_player, _square)
    if _player == nil or _player:isDead() or _player:isAsleep() then return false end
    local ok, deaf = pcall(function() return _player:hasTrait(CharacterTrait.DEAF) end)
    if ok and deaf then return false end
    if _square ~= nil then
        local mine = _player:getSquare()
        if mine == nil or mine:isOutside() ~= _square:isOutside() then return false end
    end
    return true
end

local function inRange(_player, _x, _y, _z)
    local range = COOPAudiobook.HEAR_RANGE
    return math.floor(_player:getZ()) == math.floor(_z)
            and math.abs(_player:getX() - _x) <= range
            and math.abs(_player:getY() - _y) <= range
end

local function bookOfDevice(_device)
    if _device == nil then return nil end
    local ok, id = pcall(function()
        local media = _device:getDeviceData():getMediaData()
        return media and media:getId() or nil
    end)
    if not ok then return nil end
    return COOPAudiobook.bookForMediaId(id)
end

-- On the server: world and car radios. In single player: every device, the held CD
-- player included (it reports -1 for the square, meaning whoever holds it).
local function onDeviceText(_guid, _codes, _x, _y, _z, _line, _device)
    if _codes ~= COOPAudiobook.CODES then return end
    if not COOPAudiobook.isEnabled() then return end

    local book = bookOfDevice(_device)
    if book == nil then return end

    if _x == -1 and _y == -1 and _z == -1 then
        if isServer() then return end       -- held players are reported by their client
        local holder = nil
        pcall(function() holder = _device:getPlayer() end)
        if holder ~= nil and canHear(holder, nil) then
            COOPAudiobookServer.heard(holder, book)
        end
        return
    end

    local square = getCell():getGridSquare(_x, _y, _z)
    if isServer() then
        local players = getOnlinePlayers()
        for i = 0, players:size() - 1 do
            local player = players:get(i)
            if player ~= nil and inRange(player, _x, _y, _z) and canHear(player, square) then
                COOPAudiobookServer.heard(player, book)
            end
        end
    else
        for n = 0, getNumActivePlayers() - 1 do
            local player = getSpecificPlayer(n)
            if player ~= nil and inRange(player, _x, _y, _z) and canHear(player, square) then
                COOPAudiobookServer.heard(player, book)
            end
        end
    end
end

Events.OnDeviceText.Add(onDeviceText)

-- ---------------------------------------------------------------------------
-- the computer
-- ---------------------------------------------------------------------------

local function findItem(_player, _id)
    if _id == nil then return nil end
    local ok, item = pcall(function()
        return _player:getInventory():getItemWithIDRecursiv(tonumber(_id))
    end)
    if ok then return item end
    return nil
end

local function removeItem(_item)
    local container = _item:getContainer()
    if container == nil then return end
    container:Remove(_item)
    if isServer() then sendRemoveItemFromContainer(container, _item) end
end

local function giveItem(_player, _fullType, _setup)
    local inventory = _player:getInventory()
    local item = inventory:AddItem(_fullType)
    if item == nil then return nil end
    if _setup ~= nil then _setup(item) end
    if isServer() then sendAddItemToContainer(inventory, item) end
    return item
end

-- The computer the client means, checked against the server's own map: it has to be a
-- desktop computer, within reach, and powered.
local function checkComputer(_player, _args)
    local x, y, z = tonumber(_args.x), tonumber(_args.y), tonumber(_args.z)
    if x == nil or y == nil or z == nil then return nil, "computer" end
    local reach = COOPAudiobook.REACH + 1
    if math.abs(_player:getX() - (x + 0.5)) > reach or math.abs(_player:getY() - (y + 0.5)) > reach
            or math.floor(_player:getZ()) ~= z then
        return nil, "far"
    end
    local square = getCell():getGridSquare(x, y, z)
    local computer = COOPAudiobook.findComputer(square)
    if computer == nil then return nil, "computer" end
    if not COOPAudiobook.isPowered(computer) then return nil, "power" end
    return computer
end

-- Answers the display name of what was made, or nil and a reason.
function COOPAudiobookServer.burn(_player, _args)
    if not COOPAudiobook.isEnabled() then return nil, "off" end
    if _player == nil or _args == nil then return nil, "off" end

    local computer, why = checkComputer(_player, _args)
    if computer == nil then return nil, why end

    local bookItem = findItem(_player, _args.book)
    local book = COOPAudiobook.bookForItem(bookItem)
    if book == nil then return nil, "book" end

    local blank = findItem(_player, _args.blank)
    if not COOPAudiobook.isBlank(blank) then return nil, "blank" end

    local media = COOPAudiobook.mediaFor(book)
    if media == nil then return nil, "media" end

    removeItem(blank)
    local disc = giveItem(_player, COOPAudiobook.DISC, function(item)
        item:setRecordedMediaData(media)
    end)
    if disc == nil then return nil, "full" end
    return disc:getDisplayName()
end

function COOPAudiobookServer.erase(_player, _args)
    if not COOPAudiobook.isEnabled() then return nil, "off" end
    if _player == nil or _args == nil then return nil, "off" end

    local computer, why = checkComputer(_player, _args)
    if computer == nil then return nil, why end

    local disc = findItem(_player, _args.disc)
    if not COOPAudiobook.isErasable(disc) then return nil, "disc" end

    removeItem(disc)
    local blank = giveItem(_player, COOPAudiobook.BLANK)
    if blank == nil then return nil, "full" end
    return blank:getDisplayName()
end

-- ---------------------------------------------------------------------------
-- commands
-- ---------------------------------------------------------------------------

local function reply(_player, _what, _name, _reason)
    if not isServer() then return end
    sendServerCommand(_player, COOPAudiobook.MODULE, COOPAudiobook.CMD_RESULT, {
        what = _what, name = _name, reason = _reason,
    })
end

local function onClientCommand(_module, _command, _player, _args)
    if _module ~= COOPAudiobook.MODULE then return end
    if not COOPAudiobook.isEnabled() then return end

    if _command == COOPAudiobook.CMD_BURN then
        local name, reason = COOPAudiobookServer.burn(_player, _args)
        reply(_player, "burn", name, reason)
    elseif _command == COOPAudiobook.CMD_ERASE then
        local name, reason = COOPAudiobookServer.erase(_player, _args)
        reply(_player, "erase", name, reason)
    elseif _command == COOPAudiobook.CMD_HEARD then
        -- A held CD player: only the client sees its lines, so the client's word is all
        -- there is for which book is playing. The clock between reports is the
        -- server's, though, so sending them faster than the disc plays earns nothing.
        local book = COOPAudiobook.bookForMediaId(_args and _args.media)
        if book ~= nil and canHear(_player, nil) then
            COOPAudiobookServer.heard(_player, book)
        end
    end
end

Events.OnClientCommand.Add(onClientCommand)
