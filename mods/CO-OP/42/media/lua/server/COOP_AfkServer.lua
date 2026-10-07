--
-- CO-OP - AFK authority: who is AFK, and keeping them frozen.
--
-- Runs on the dedicated/hosted server, and also in single player where there is no
-- server process (the client calls these functions directly). The client decides when
-- its own player has been idle long enough and when they are back; the server owns the
-- list everyone else reads, holds the snapshot and writes it back every tick, and ends
-- an AFK by itself when the player is hurt, walks off or leaves.
--

if isClient() then return end

require "COOP_Afk"

COOPAfkServer = {}

-- name -> { player, snap, x, y, z, vehicle }
local entries = {}

local GONE_CHECK_TICKS = 60
local ticks = 0

local function vehicleOf(_player)
    local vehicle = nil
    pcall(function() vehicle = _player:getVehicle() end)
    return vehicle
end

-- Auto-drink runs on the server in multiplayer (IsoGameCharacter.autoDrink returns at
-- once on a client), drinking straight from a bottle with no timed action. With thirst
-- held above the threshold it would sip the AFK player's water away a mouthful at a
-- time, so the player's own auto-drink flag is switched off for the duration. Answers
-- whether it was on, so stop() can put it back. In single player the flag is not read -
-- the client blocks it through the AutoDrink hook instead (COOP_AfkUI.lua).
local function setAutoDrink(_player, _on)
    local was = false
    pcall(function()
        was = _player:getAutoDrink() == true
        _player:setAutoDrink(_on)
    end)
    return was
end

-- Tells every client (or, in single player, the local UI) what changed.
local function announce(_name, _on, _reason)
    local args = { name = _name, on = _on, reason = _reason }
    if isServer() then
        sendServerCommand(COOPAfk.MODULE, COOPAfk.CMD_STATE, args)
    elseif COOPAfkUI ~= nil and COOPAfkUI.onState ~= nil then
        COOPAfkUI.onState(args)
    end
end

local function refuse(_player, _name)
    if isServer() then
        sendServerCommand(_player, COOPAfk.MODULE, COOPAfk.CMD_STATE,
                { name = _name, on = false, reason = COOPAfk.R_REFUSED })
    elseif COOPAfkUI ~= nil and COOPAfkUI.onState ~= nil then
        COOPAfkUI.onState({ name = _name, on = false, reason = COOPAfk.R_REFUSED })
    end
end

local function canGoAfk(_player)
    if not COOPAfk.isEnabled() then return false end
    local ok, fine = pcall(function()
        return not _player:isDead() and not _player:isAsleep()
    end)
    return ok and fine
end

function COOPAfkServer.start(_player)
    if _player == nil then return false end
    local name = COOP.playerName(_player)

    if not canGoAfk(_player) then
        refuse(_player, name)
        return false
    end
    if entries[name] ~= nil then return true end

    entries[name] = {
        player = _player,
        snap = COOPAfk.snapshot(_player),
        x = _player:getX(), y = _player:getY(), z = _player:getZ(),
        vehicle = vehicleOf(_player),
        autoDrink = setAutoDrink(_player, false),
    }
    COOPAfk.names[name] = true
    announce(name, true, nil)
    COOP.log(name .. " is AFK")
    return true
end

function COOPAfkServer.stop(_name, _reason)
    if _name == nil or entries[_name] == nil then return false end
    local entry = entries[_name]
    if entry.autoDrink then setAutoDrink(entry.player, true) end
    entries[_name] = nil
    COOPAfk.names[_name] = nil
    announce(_name, false, _reason or COOPAfk.R_BACK)
    COOP.log(_name .. " is back from AFK (" .. tostring(_reason or COOPAfk.R_BACK) .. ")")
    return true
end

function COOPAfkServer.stopPlayer(_player, _reason)
    if _player == nil then return false end
    return COOPAfkServer.stop(COOP.playerName(_player), _reason)
end

function COOPAfkServer.getNames()
    local out = {}
    for name in pairs(entries) do out[name] = true end
    return out
end

-- ---------------------------------------------------------------------------
-- the freeze
-- ---------------------------------------------------------------------------

local function onlineNames()
    local names = {}
    COOPAfk.eachPlayer(function(_player) names[COOP.playerName(_player)] = _player end)
    return names
end

local function moved(_entry, _player)
    if vehicleOf(_player) ~= _entry.vehicle then return true end
    local dx = _player:getX() - _entry.x
    local dy = _player:getY() - _entry.y
    if math.floor(_player:getZ()) ~= math.floor(_entry.z) then return true end
    return dx * dx + dy * dy > COOPAfk.SERVER_MOVE_LIMIT * COOPAfk.SERVER_MOVE_LIMIT
end

local function onTick()
    if COOPAfk.isEmpty(entries) then return end

    if not COOPAfk.isEnabled() then
        for name in pairs(entries) do COOPAfkServer.stop(name, COOPAfk.R_OFF) end
        return
    end

    -- A disconnected player's IsoPlayer lingers for a while; the online list is the
    -- truth, and the object is re-resolved from it in case the player relogged.
    ticks = ticks + 1
    if ticks >= GONE_CHECK_TICKS then
        ticks = 0
        local online = onlineNames()
        for name, entry in pairs(entries) do
            if online[name] == nil then
                COOPAfkServer.stop(name, COOPAfk.R_GONE)
            else
                entry.player = online[name]
            end
        end
    end

    for name, entry in pairs(entries) do
        local player = entry.player
        local ok, err = pcall(function()
            if player:isDead() then
                COOPAfkServer.stop(name, COOPAfk.R_GONE)
            elseif moved(entry, player) then
                COOPAfkServer.stop(name, COOPAfk.R_MOVED)
            elseif COOPAfk.wasHurt(player, entry.snap) then
                -- The hit stands: the snapshot is dropped, not written back over it.
                COOPAfkServer.stop(name, COOPAfk.R_HURT)
            else
                COOPAfk.restore(player, entry.snap)
            end
        end)
        if not ok then
            COOP.log("AFK freeze failed for " .. name .. ": " .. tostring(err))
            COOPAfkServer.stop(name, COOPAfk.R_GONE)
        end
    end
end

Events.OnTick.Add(onTick)

-- ---------------------------------------------------------------------------
-- commands
-- ---------------------------------------------------------------------------

local function onClientCommand(_module, _command, _player, _args)
    if _module ~= COOPAfk.MODULE then return end

    if _command == COOPAfk.CMD_ON then
        COOPAfkServer.start(_player)
    elseif _command == COOPAfk.CMD_OFF then
        COOPAfkServer.stopPlayer(_player, COOPAfk.R_BACK)
    elseif _command == COOPAfk.CMD_REQUEST_SYNC then
        if not isServer() then return end
        sendServerCommand(_player, COOPAfk.MODULE, COOPAfk.CMD_SYNC,
                { names = COOPAfkServer.getNames() })
    end
end

Events.OnClientCommand.Add(onClientCommand)
