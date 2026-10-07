--
-- CO-OP - authority over reglazing a smashed window.
--
-- Runs on the dedicated/hosted server, and also in single player where there is no
-- server process and the client calls COOPGlassServer.reglaze directly.
--
-- The panes are items and the window is a map object, both the server's: so the client's
-- action only plays the work and then says "I glazed the window here, facing so", and
-- this file re-checks everything, takes the panes, restores the window and awards the XP
-- (addXp does nothing at all when called on a multiplayer client - see
-- COOP_ClayServer.lua).
--
-- Restoring is one call. In the engine "smashed" is IsoWindow's `destroyed` field, and
-- setSmashed(false) - read out of its bytecode - clears it, puts back the open or closed
-- sprite, resets the health to the maximum and clears glassRemoved too.
-- setGlassRemoved(false) follows anyway because it is the one that tells the path
-- finder the square changed. sync() is what vanilla's ISRemoveBrokenGlass calls after
-- removeBrokenGlass, and its payload carries both flags and the health.
--

if isClient() then return end

require "COOP_Glass"

COOPGlassServer = {}

local writeBudget = {}

local function rateLimited(_playerObj)
    local key = COOP.playerName(_playerObj)
    local now = getTimestampMs()
    local budget = writeBudget[key]

    if budget == nil or now - budget.start > COOPGlass.WRITE_WINDOW_MS then
        writeBudget[key] = { start = now, count = 1 }
        return false
    end

    budget.count = budget.count + 1
    return budget.count > COOPGlass.WRITE_LIMIT
end

local function reply(_playerObj, _ok, _reason)
    if not isServer() then return end
    sendServerCommand(_playerObj, COOPGlass.MODULE, COOPGlass.CMD_RESULT, {
        ok = _ok,
        reason = _reason,
    })
end

-- Takes the panes out of wherever on the character they are, bags included, and tells
-- the clients each one is gone.
local function takePanes(_character, _count)
    local items = _character:getInventory():getAllTypeRecurse(COOPGlass.PANE)
    if items == nil or items:size() < _count then return false end

    for i = 0, _count - 1 do
        local item = items:get(i)
        local container = item:getContainer()
        if container ~= nil then
            if _character:isEquipped(item) then _character:removeFromHands(item) end
            container:Remove(item)
            sendRemoveItemFromContainer(container, item)
        end
    end
    return true
end

-- Answers true, or false with a reason. The client is trusted only for which window it
-- meant.
function COOPGlassServer.reglaze(_playerObj, _args)
    if not COOPGlass.isEnabled() then return false, "off" end
    if _playerObj == nil or _args == nil then return false, "off" end
    if rateLimited(_playerObj) then return false, "rate" end

    local x = tonumber(_args.x)
    local y = tonumber(_args.y)
    local z = tonumber(_args.z)
    if x == nil or y == nil or z == nil then return false, "where" end

    if math.abs(_playerObj:getX() - x) > COOPGlass.REACH + 1
            or math.abs(_playerObj:getY() - y) > COOPGlass.REACH + 1 then
        return false, "far"
    end

    local cell = getCell()
    local square = cell ~= nil and cell:getGridSquare(x, y, z) or nil
    local window = COOPGlass.findWindow(square, _args.north == true)
    if window == nil then return false, "where" end

    local problem = COOPGlass.reglazeProblem(_playerObj, window)
    if problem ~= nil then return false, problem end

    if not takePanes(_playerObj, COOPGlass.PANES_PER_WINDOW) then return false, "panes" end

    window:setSmashed(false)
    window:setGlassRemoved(false)
    if isServer() then window:sync() end

    local perk = COOPGlass.perk()
    if perk ~= nil and COOPGlass.REGLAZE_XP > 0 then
        pcall(function() addXp(_playerObj, perk, COOPGlass.REGLAZE_XP) end)
    end

    COOP.log(COOP.playerName(_playerObj) .. " reglazed the window at "
            .. x .. "," .. y .. "," .. z .. (_args.north and " (N)" or " (W)"))

    return true
end

local function onClientCommand(_module, _command, _playerObj, _args)
    if _module ~= COOPGlass.MODULE then return end
    if _command ~= COOPGlass.CMD_REGLAZE then return end
    if not COOPGlass.isEnabled() then return end

    local ok, reason = COOPGlassServer.reglaze(_playerObj, _args)
    reply(_playerObj, ok, reason)
end

Events.OnClientCommand.Add(onClientCommand)
