--
-- CO-OP - authority over the shared to-do list.
--
-- Runs on the dedicated/hosted server, and also in single player where there is no
-- server process (the client calls these functions directly).
--

if isClient() then return end

require "COOP_Todo"

COOPTodoServer = {}

local writeBudget = {}

local function ensureData()
    local data = ModData.getOrCreate(COOPTodo.MODDATA_KEY)
    if data.version == nil then data.version = COOPTodo.SCHEMA end
    if data.entries == nil then data.entries = {} end
    if data.nextId == nil then data.nextId = 1 end
    return data
end

local function broadcast(_id, _entry)
    if not isServer() then return end
    sendServerCommand(COOPTodo.MODULE, COOPTodo.CMD_DELTA, {
        id = _id,
        entry = _entry,
        removed = _entry == nil,
    })
end

-- Tells everyone what somebody just did, so a shared list is noticed without opening
-- it. One notice per action, not per entry. The text travels with it because a removal
-- leaves nothing in the state for the receiving client to name - and the name is the
-- server's, never the client's, exactly as it is for pings.
local function notify(_playerObj, _action, _text, _count)
    if not isServer() then return end
    sendServerCommand(COOPTodo.MODULE, COOPTodo.CMD_NOTICE, {
        action = _action,
        by = COOP.playerName(_playerObj),
        text = _text,
        count = _count,
    })
end

-- Allows a burst (ticking several lines off at once) but not a flood.
local function rateLimited(_playerObj)
    local key = COOP.playerName(_playerObj)
    local now = getTimestampMs()
    local budget = writeBudget[key]

    if budget == nil or now - budget.start > COOPTodo.WRITE_WINDOW_MS then
        writeBudget[key] = { start = now, count = 1 }
        return false
    end

    budget.count = budget.count + 1
    return budget.count > COOPTodo.WRITE_LIMIT
end

local function countEntries(_data)
    local count = 0
    for _ in pairs(_data.entries) do count = count + 1 end
    return count
end

function COOPTodoServer.getEntries()
    return ensureData().entries
end

function COOPTodoServer.add(_playerObj, _text)
    local text = COOPTodo.cleanText(_text)
    if text == nil then return false end
    if rateLimited(_playerObj) then return false end

    local data = ensureData()
    if countEntries(data) >= COOPTodo.maxEntries() then
        COOP.log("to-do list is full, refusing to add another line")
        return false
    end

    local id = tostring(data.nextId)
    data.nextId = data.nextId + 1

    local entry = {
        id = id,
        text = text,
        by = COOP.playerName(_playerObj),
        when = COOP.gameDateString(),
        at = COOP.worldAgeHours(),
        done = false,
    }
    data.entries[id] = entry

    broadcast(id, entry)
    notify(_playerObj, COOPTodo.ACT_ADD, text)
    COOP.log(entry.by .. " added to-do #" .. id .. ": " .. text)
    return true
end

function COOPTodoServer.edit(_playerObj, _id, _text)
    local id = COOPTodo.cleanId(_id)
    local text = COOPTodo.cleanText(_text)
    if id == nil or text == nil then return false end

    local data = ensureData()
    local entry = data.entries[id]
    if entry == nil then return false end
    if rateLimited(_playerObj) then return false end

    entry.text = text
    broadcast(id, entry)
    notify(_playerObj, COOPTodo.ACT_EDIT, text)
    return true
end

-- Ticking a line off records who did it, which is the whole point of a shared list.
function COOPTodoServer.setDone(_playerObj, _id, _done)
    local id = COOPTodo.cleanId(_id)
    if id == nil then return false end

    local data = ensureData()
    local entry = data.entries[id]
    if entry == nil then return false end
    if rateLimited(_playerObj) then return false end

    local done = _done == true
    if entry.done == done then return false end

    entry.done = done
    if done then
        entry.doneBy = COOP.playerName(_playerObj)
        entry.doneWhen = COOP.gameDateString()
    else
        entry.doneBy = nil
        entry.doneWhen = nil
    end

    broadcast(id, entry)
    notify(_playerObj, done and COOPTodo.ACT_DONE or COOPTodo.ACT_UNDONE, entry.text)
    return true
end

function COOPTodoServer.remove(_playerObj, _id)
    local id = COOPTodo.cleanId(_id)
    if id == nil then return false end

    local data = ensureData()
    local entry = data.entries[id]
    if entry == nil then return false end
    if rateLimited(_playerObj) then return false end

    data.entries[id] = nil
    broadcast(id, nil)
    notify(_playerObj, COOPTodo.ACT_REMOVE, entry.text)
    COOP.log(COOP.playerName(_playerObj) .. " removed to-do #" .. id)
    return true
end

function COOPTodoServer.clearDone(_playerObj)
    if rateLimited(_playerObj) then return false end

    local data = ensureData()
    local removed = {}
    for id, entry in pairs(data.entries) do
        if COOPTodo.isDone(entry) then table.insert(removed, id) end
    end
    if #removed == 0 then return false end

    for _, id in ipairs(removed) do
        data.entries[id] = nil
        broadcast(id, nil)
    end
    notify(_playerObj, COOPTodo.ACT_CLEAR, nil, #removed)

    COOP.log(COOP.playerName(_playerObj) .. " cleared " .. #removed .. " finished to-do lines")
    return true
end

local function sendSync(_playerObj)
    if not isServer() then return end
    local data = ensureData()
    sendServerCommand(_playerObj, COOPTodo.MODULE, COOPTodo.CMD_SYNC, {
        entries = data.entries,
        version = data.version,
    })
end

local function onClientCommand(_module, _command, _playerObj, _args)
    if _module ~= COOPTodo.MODULE then return end
    if not COOP.featureEnabled(COOP.F_TODO) then return end
    _args = _args or {}

    if _command == COOPTodo.CMD_SYNC_REQUEST then
        sendSync(_playerObj)
    elseif _command == COOPTodo.CMD_ADD then
        COOPTodoServer.add(_playerObj, _args.text)
    elseif _command == COOPTodo.CMD_EDIT then
        COOPTodoServer.edit(_playerObj, _args.id, _args.text)
    elseif _command == COOPTodo.CMD_TOGGLE then
        COOPTodoServer.setDone(_playerObj, _args.id, _args.done)
    elseif _command == COOPTodo.CMD_REMOVE then
        COOPTodoServer.remove(_playerObj, _args.id)
    elseif _command == COOPTodo.CMD_CLEAR_DONE then
        COOPTodoServer.clearDone(_playerObj)
    end
end

Events.OnClientCommand.Add(onClientCommand)

Events.OnInitGlobalModData.Add(function()
    ensureData()
    COOP.log("to-do list ready")
end)
