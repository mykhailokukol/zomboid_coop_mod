--
-- CO-OP - client-side view of the shared to-do list.
--
-- In multiplayer this is a cache fed by the server; in single player it reads the
-- server table directly, since both halves live in the same Lua state.
--

if isServer() then return end

require "COOP_Todo"

COOPTodoState = COOPTodoState or {}
COOPTodoState.rev = 0  -- bumped on every change so an open window knows to rebuild

local cache = {}
local synced = false
local nextRequestMs = 0

local REQUEST_RETRY_MS = 10000

local function bump()
    COOPTodoState.rev = COOPTodoState.rev + 1
end

function COOPTodoState.isSynced()
    if not isClient() then return true end
    return synced
end

function COOPTodoState.getEntries()
    if isClient() then return cache end
    if COOPTodoServer then return COOPTodoServer.getEntries() end
    return {}
end

function COOPTodoState.getEntry(_id)
    local id = COOPTodo.cleanId(_id)
    if id == nil then return nil end
    return COOPTodoState.getEntries()[id]
end

-- Entries in display order: open lines first, oldest first.
function COOPTodoState.getSorted()
    local list = {}
    for _, entry in pairs(COOPTodoState.getEntries()) do
        table.insert(list, entry)
    end
    table.sort(list, COOPTodo.sorter)
    return list
end

function COOPTodoState.counts()
    local open, done = 0, 0
    for _, entry in pairs(COOPTodoState.getEntries()) do
        if COOPTodo.isDone(entry) then done = done + 1 else open = open + 1 end
    end
    return open, done
end

local function request(_command, _args)
    if isClient() then
        local player = getPlayer()
        if player == nil then return end
        sendClientCommand(player, COOPTodo.MODULE, _command, _args or {})
        return
    end

    -- Single player: no round trip, call the authority directly.
    if COOPTodoServer == nil then
        COOP.log("to-do server module missing, cannot " .. tostring(_command))
        return
    end

    local player = getPlayer()
    local args = _args or {}
    if _command == COOPTodo.CMD_ADD then
        COOPTodoServer.add(player, args.text)
    elseif _command == COOPTodo.CMD_EDIT then
        COOPTodoServer.edit(player, args.id, args.text)
    elseif _command == COOPTodo.CMD_TOGGLE then
        COOPTodoServer.setDone(player, args.id, args.done)
    elseif _command == COOPTodo.CMD_REMOVE then
        COOPTodoServer.remove(player, args.id)
    elseif _command == COOPTodo.CMD_CLEAR_DONE then
        COOPTodoServer.clearDone(player)
    end
    bump()
end

function COOPTodoState.add(_text)
    local text = COOPTodo.cleanText(_text)
    if text == nil then return end
    request(COOPTodo.CMD_ADD, { text = text })
end

function COOPTodoState.edit(_id, _text)
    local text = COOPTodo.cleanText(_text)
    if text == nil then return end
    request(COOPTodo.CMD_EDIT, { id = _id, text = text })
end

function COOPTodoState.setDone(_id, _done)
    request(COOPTodo.CMD_TOGGLE, { id = _id, done = _done == true })
end

function COOPTodoState.toggle(_id)
    local entry = COOPTodoState.getEntry(_id)
    if entry == nil then return end
    COOPTodoState.setDone(_id, not COOPTodo.isDone(entry))
end

function COOPTodoState.remove(_id)
    request(COOPTodo.CMD_REMOVE, { id = _id })
end

function COOPTodoState.clearDone()
    request(COOPTodo.CMD_CLEAR_DONE, {})
end

-- One line in chat per change somebody else made. A shared list nobody looks at is a
-- list nobody uses, and the window is behind a key. Your own changes are skipped: you
-- are looking at the list you just edited.
--
-- Trimmed harder than the stored text, which can run to TEXT_MAX and would push the
-- rest of the chat line out of view.
local CHAT_TEXT_MAX = 60

local function announce(_args)
    if _args == nil or _args.action == nil then return end
    if not COOP.featureEnabled(COOP.F_TODO) then return end
    if COOP.option("TodoChatLine", true) == false then return end

    local by = tostring(_args.by or "?")
    if by == COOP.playerName(getPlayer()) then return end

    local key = COOPTodo.ACT_TEXT[_args.action]
    if key == nil then return end

    local what = _args.text
    if what ~= nil then
        what = tostring(what)
        if #what > CHAT_TEXT_MAX then what = string.sub(what, 1, CHAT_TEXT_MAX) .. "..." end
    else
        what = tostring(_args.count or 0)
    end

    -- the same colour this player's pings use, so a name reads the same wherever it
    -- shows. Not required: the line is readable in the chat's own colour without it.
    local r, g, b
    if COOPPing ~= nil and COOPPing.colourFor ~= nil then
        r, g, b = COOPPing.colourFor(by)
    end
    COOP.sayInChat(getText(key, by, what), r, g, b)
end

local function onServerCommand(_module, _command, _args)
    if _module ~= COOPTodo.MODULE then return end

    if _command == COOPTodo.CMD_SYNC then
        cache = (_args and _args.entries) or {}
        synced = true
        bump()
        COOP.log("received the to-do list from the server")
    elseif _command == COOPTodo.CMD_DELTA then
        if _args == nil or _args.id == nil then return end
        if _args.removed or _args.entry == nil then
            cache[_args.id] = nil
        else
            cache[_args.id] = _args.entry
        end
        bump()
    elseif _command == COOPTodo.CMD_NOTICE then
        announce(_args)
    end
end

local function requestSync()
    if not isClient() then return end
    nextRequestMs = getTimestampMs() + REQUEST_RETRY_MS
    sendClientCommand(getPlayer(), COOPTodo.MODULE, COOPTodo.CMD_SYNC_REQUEST, {})
end

-- Keep asking until the server answers: the first request can land before the player
-- is fully connected.
local function onTick()
    if not isClient() or synced then return end
    if getPlayer() == nil then return end
    if getTimestampMs() < nextRequestMs then return end
    requestSync()
end

Events.OnServerCommand.Add(onServerCommand)
Events.OnTick.Add(onTick)
Events.OnCreatePlayer.Add(function()
    synced = false
    nextRequestMs = 0
end)
