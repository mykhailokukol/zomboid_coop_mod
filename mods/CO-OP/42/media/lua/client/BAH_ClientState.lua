--
-- CO-OP / Books at home - client-side view of the shared list.
--
-- In multiplayer this is a cache fed by the server; in single player it reads the
-- server table directly, since both halves live in the same Lua state.
--

if isServer() then return end

require "BAH_Common"
require "BAH_Catalog"

BooksAtHome = BooksAtHome or {}
BooksAtHome.rev = 0  -- bumped on every change so open windows know to rebuild

local cache = {}
local synced = false
local nextRequestMs = 0

local REQUEST_RETRY_MS = 10000

local function bump()
    BooksAtHome.rev = BooksAtHome.rev + 1
end

function BooksAtHome.isSynced()
    if not isClient() then return true end
    return synced
end

function BooksAtHome.getEntries()
    if isClient() then return cache end
    if BooksAtHomeServer then return BooksAtHomeServer.getEntries() end
    return {}
end

function BooksAtHome.getEntry(_key)
    if _key == nil then return nil end
    return BooksAtHome.getEntries()[_key]
end

function BooksAtHome.isMarked(_key)
    return BooksAtHome.getEntry(_key) ~= nil
end

function BooksAtHome.canReset()
    if not isClient() then return true end
    local ok, admin = pcall(function() return isAdmin() end)
    return ok and admin == true
end

local function request(_command, _args)
    if isClient() then
        local player = getPlayer()
        if player == nil then return end
        sendClientCommand(player, BAH.MODULE, _command, _args or {})
        return
    end

    -- Single player: no round trip, call the authority directly.
    if BooksAtHomeServer == nil then
        BAH.log("server module missing, cannot " .. tostring(_command))
        return
    end
    local player = getPlayer()
    local args = _args or {}
    if _command == "set" then
        BooksAtHomeServer.set(player, args.type, args.note)
    elseif _command == "unset" then
        BooksAtHomeServer.unset(player, args.type)
    elseif _command == "setNote" then
        BooksAtHomeServer.setNote(player, args.type, args.note)
    elseif _command == "reset" then
        BooksAtHomeServer.reset(player)
    end
    bump()
end

function BooksAtHome.mark(_key, _note)
    if not BAH.isTrackable(_key) then return end
    request("set", { type = _key, note = BAH.cleanNote(_note) })
end

function BooksAtHome.unmark(_key)
    request("unset", { type = _key })
end

function BooksAtHome.setNote(_key, _note)
    if not BAH.isTrackable(_key) then return end
    request("setNote", { type = _key, note = BAH.cleanNote(_note) })
end

function BooksAtHome.toggle(_key, _note)
    if BooksAtHome.isMarked(_key) then
        BooksAtHome.unmark(_key)
    else
        BooksAtHome.mark(_key, _note)
    end
end

function BooksAtHome.reset()
    if not BooksAtHome.canReset() then return end
    request("reset", {})
end

local function onServerCommand(_module, _command, _args)
    if _module ~= BAH.MODULE then return end

    if _command == "sync" then
        cache = (_args and _args.entries) or {}
        synced = true
        bump()
        BAH.log("received list from server")
    elseif _command == "delta" then
        if _args == nil or _args.type == nil then return end
        if _args.removed or _args.entry == nil then
            cache[_args.type] = nil
        else
            cache[_args.type] = _args.entry
        end
        bump()
    end
end

local function requestSync()
    if not isClient() then return end
    nextRequestMs = getTimestampMs() + REQUEST_RETRY_MS
    sendClientCommand(getPlayer(), BAH.MODULE, "requestSync", {})
end

-- Keep asking until the server answers: the first request can land before the
-- player is fully connected.
local function onTick()
    if not isClient() or synced then return end
    if getPlayer() == nil then return end
    if getTimestampMs() < nextRequestMs then return end
    requestSync()
end

Events.OnServerCommand.Add(onServerCommand)
Events.OnTick.Add(onTick)
Events.OnGameStart.Add(function()
    synced = not isClient()
    cache = {}
    nextRequestMs = 0
end)
