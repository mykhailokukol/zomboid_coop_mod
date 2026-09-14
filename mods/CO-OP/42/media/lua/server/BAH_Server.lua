--
-- CO-OP / Books at home - authority over the shared list.
--
-- Runs on the dedicated/hosted server, and also in single player where there is
-- no server process (the client calls these functions directly).
--

if isClient() then return end

require "BAH_Common"
require "BAH_Catalog"

BooksAtHomeServer = {}

local writeBudget = {}

local function ensureData()
    local data = ModData.getOrCreate(BAH.MODDATA_KEY)
    if data.version == nil then data.version = BAH.SCHEMA end
    if data.entries == nil then data.entries = {} end
    return data
end

local function broadcast(_key, _entry)
    if not isServer() then return end
    sendServerCommand(BAH.MODULE, "delta", {
        type = _key,
        entry = _entry,
        removed = _entry == nil,
    })
end

-- Allows a burst (marking a stack of books at once) but not a flood.
local function rateLimited(_playerObj)
    local key = BAH.playerName(_playerObj)
    local now = getTimestampMs()
    local budget = writeBudget[key]

    if budget == nil or now - budget.start > BAH.WRITE_WINDOW_MS then
        writeBudget[key] = { start = now, count = 1 }
        return false
    end

    budget.count = budget.count + 1
    if budget.count > BAH.WRITE_LIMIT then
        return true
    end
    return false
end

local function isStaff(_playerObj)
    if _playerObj == nil then return false end
    local ok, level = pcall(function() return _playerObj:getAccessLevel() end)
    if not ok or level == nil then return false end
    level = string.lower(tostring(level))
    return level == "admin" or level == "moderator" or level == "overseer"
end

function BooksAtHomeServer.getEntries()
    return ensureData().entries
end

function BooksAtHomeServer.getEntry(_key)
    return ensureData().entries[_key]
end

-- Marks a book as being at home. Returns true when something changed.
function BooksAtHomeServer.set(_playerObj, _key, _note)
    if not BAH.isTrackable(_key) then return false end
    if rateLimited(_playerObj) then return false end

    local data = ensureData()
    local entry = {
        by = BAH.playerName(_playerObj),
        when = BAH.gameDateString(),
        at = BAH.worldAgeHours(),
        note = BAH.cleanNote(_note),
    }
    data.entries[_key] = entry
    broadcast(_key, entry)
    BAH.log(entry.by .. " marked " .. _key .. " as at home" ..
            (entry.note and (" (" .. entry.note .. ")") or ""))
    return true
end

function BooksAtHomeServer.unset(_playerObj, _key)
    local data = ensureData()
    if data.entries[_key] == nil then return false end
    if rateLimited(_playerObj) then return false end

    data.entries[_key] = nil
    broadcast(_key, nil)
    BAH.log(BAH.playerName(_playerObj) .. " unmarked " .. _key)
    return true
end

function BooksAtHomeServer.setNote(_playerObj, _key, _note)
    local data = ensureData()
    local entry = data.entries[_key]
    if entry == nil then
        -- Editing the note of an unmarked book marks it.
        return BooksAtHomeServer.set(_playerObj, _key, _note)
    end
    if rateLimited(_playerObj) then return false end

    entry.note = BAH.cleanNote(_note)
    entry.by = BAH.playerName(_playerObj)
    entry.when = BAH.gameDateString()
    entry.at = BAH.worldAgeHours()
    broadcast(_key, entry)
    return true
end

function BooksAtHomeServer.reset(_playerObj)
    local data = ensureData()
    data.entries = {}
    if isServer() then
        sendServerCommand(BAH.MODULE, "sync", { entries = data.entries, version = data.version })
    end
    BAH.log(BAH.playerName(_playerObj) .. " cleared the whole list")
    return true
end

local function sendSync(_playerObj)
    if not isServer() then return end
    local data = ensureData()
    sendServerCommand(_playerObj, BAH.MODULE, "sync", {
        entries = data.entries,
        version = data.version,
    })
end

local function onClientCommand(_module, _command, _playerObj, _args)
    if _module ~= BAH.MODULE then return end
    _args = _args or {}

    if _command == "requestSync" then
        sendSync(_playerObj)
    elseif _command == "set" then
        BooksAtHomeServer.set(_playerObj, _args.type, _args.note)
    elseif _command == "unset" then
        BooksAtHomeServer.unset(_playerObj, _args.type)
    elseif _command == "setNote" then
        BooksAtHomeServer.setNote(_playerObj, _args.type, _args.note)
    elseif _command == "reset" then
        if isStaff(_playerObj) then
            BooksAtHomeServer.reset(_playerObj)
        else
            BAH.log(BAH.playerName(_playerObj) .. " tried to clear the list without permission")
        end
    end
end

Events.OnClientCommand.Add(onClientCommand)

Events.OnInitGlobalModData.Add(function()
    ensureData()
    BAH.log("server data ready")
end)
