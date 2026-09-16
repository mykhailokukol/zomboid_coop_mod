--
-- CO-OP - the shared to-do list.
--
-- One list per server: anybody can add a line, tick it off, edit it or delete it, and
-- everyone sees the change at once. Same shape as the books list - the server owns the
-- table, clients hold a cache and ask for changes - because that is what keeps two
-- players ticking the same line from diverging.
--
-- The state rides along in the save as GlobalModData; no file I/O, nothing to migrate.
--

require "COOP_Common"

COOPTodo = COOPTodo or {}

COOPTodo.MODULE = "CO-OP"
COOPTodo.MODDATA_KEY = "COOP_Todo"
COOPTodo.SCHEMA = 1

COOPTodo.TEXT_MAX = 120         -- characters kept from one line
COOPTodo.MAX_ENTRIES = 200      -- default cap; the sandbox option overrides it
COOPTodo.WRITE_WINDOW_MS = 2000 -- rate limit window, per player
COOPTodo.WRITE_LIMIT = 20       -- writes allowed inside that window

-- commands on the mod channel
COOPTodo.CMD_SYNC_REQUEST = "todoRequestSync"
COOPTodo.CMD_SYNC = "todoSync"
COOPTodo.CMD_DELTA = "todoDelta"
COOPTodo.CMD_ADD = "todoAdd"
COOPTodo.CMD_EDIT = "todoEdit"
COOPTodo.CMD_TOGGLE = "todoToggle"
COOPTodo.CMD_REMOVE = "todoRemove"
COOPTodo.CMD_CLEAR_DONE = "todoClearDone"
COOPTodo.CMD_NOTICE = "todoNotice"

-- What a notice is about. The delta that carries the state change stays a pure state
-- message; this is the human-readable half, sent once per thing a player did rather
-- than once per entry, so clearing ten finished lines is one line in chat and not ten.
COOPTodo.ACT_ADD = "add"
COOPTodo.ACT_EDIT = "edit"
COOPTodo.ACT_DONE = "done"
COOPTodo.ACT_UNDONE = "undone"
COOPTodo.ACT_REMOVE = "remove"
COOPTodo.ACT_CLEAR = "clear"

-- The chat wording for each, by action.
COOPTodo.ACT_TEXT = {
    [COOPTodo.ACT_ADD] = "UI_COOP_Todo_Chat_Added",
    [COOPTodo.ACT_EDIT] = "UI_COOP_Todo_Chat_Edited",
    [COOPTodo.ACT_DONE] = "UI_COOP_Todo_Chat_Done",
    [COOPTodo.ACT_UNDONE] = "UI_COOP_Todo_Chat_Undone",
    [COOPTodo.ACT_REMOVE] = "UI_COOP_Todo_Chat_Removed",
    [COOPTodo.ACT_CLEAR] = "UI_COOP_Todo_Chat_Cleared",
}

-- Trims a line to something safe to store and draw: no control characters, no runaway
-- length, and nil when nothing readable is left.
function COOPTodo.cleanText(_text)
    if _text == nil then return nil end

    local text = tostring(_text)
    text = string.gsub(text, "[%c]", " ")
    text = string.gsub(text, "%s+", " ")
    text = string.trim(text)

    if text == "" then return nil end
    if #text > COOPTodo.TEXT_MAX then text = string.sub(text, 1, COOPTodo.TEXT_MAX) end
    return text
end

-- Entry ids are strings on purpose: they are table keys that travel over the command
-- channel, and a table keyed by strings survives that trip without any doubt about
-- whether an integer key came back as an integer.
function COOPTodo.cleanId(_id)
    if _id == nil then return nil end
    local id = tostring(_id)
    if not string.match(id, "^%d+$") then return nil end
    return id
end

function COOPTodo.maxEntries()
    return COOP.numberOption("TodoMaxEntries", COOPTodo.MAX_ENTRIES, 20, 500)
end

function COOPTodo.isDone(_entry)
    return _entry ~= nil and _entry.done == true
end

-- Open lines first, then the done ones; oldest first inside each group.
function COOPTodo.sorter(_a, _b)
    local aDone = COOPTodo.isDone(_a)
    local bDone = COOPTodo.isDone(_b)
    if aDone ~= bDone then return bDone end
    return (_a.at or 0) < (_b.at or 0)
end
