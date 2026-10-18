--
-- CO-OP - the boombox: the authority. Which boomboxes are playing what, for everyone.
--
-- Runs on the server, and in single player where there is no server process and the
-- client calls straight in (COOPBoomboxUI.send).
--
-- A boombox plays only while it is in its holder's hands. Every command is checked
-- against that, and once a second every playing boombox is checked again: put away,
-- dropped, holder gone or dead, and it goes quiet for everyone. It is not remembered
-- anywhere - a boombox picked up again starts with nothing playing - so there is nothing
-- in the save either.
--
-- The position is kept as `pos` seconds at server time `since`. Clients are sent the
-- position as of the moment of sending and count on from when it arrives, on their own
-- clock; nobody's clock has to agree with anybody else's.
--

if isClient() then return end

require "COOP_Boombox"

COOPBoomboxServer = {}

-- item id -> { id, holder, name, url, title, duration, volume, paused, pos, since }
local boxes = {}

local CHECK_MS = 1000
local NOISE_MS = 3000
local lastCheck = 0
local lastNoise = 0

local function now() return getTimestampMs() end

local function positionOf(_box)
    if _box.paused then return _box.pos end
    return _box.pos + math.max(0, (now() - _box.since) / 1000)
end

-- What a client gets: plain values only.
local function payload(_box)
    return {
        id = _box.id,
        holder = _box.holder,
        name = _box.name,
        url = _box.url,
        title = _box.title,
        duration = _box.duration,
        volume = _box.volume,
        paused = _box.paused,
        pos = positionOf(_box),
    }
end

-- To everyone. In single player there is one client, in this same Lua state.
local function broadcast(_command, _args)
    if isServer() then
        sendServerCommand(COOPBoombox.MODULE, _command, _args)
    elseif COOPBoomboxUI ~= nil then
        COOPBoomboxUI.onServerCommand(COOPBoombox.MODULE, _command, _args)
    end
end

local function tell(_player, _command, _args)
    if isServer() then
        sendServerCommand(_player, COOPBoombox.MODULE, _command, _args)
    elseif COOPBoomboxUI ~= nil then
        COOPBoomboxUI.onServerCommand(COOPBoombox.MODULE, _command, _args)
    end
end

local function changed(_box)
    broadcast(COOPBoombox.CMD_STATE, payload(_box))
end

local function silence(_id, _why)
    local box = boxes[_id]
    if box == nil then return end
    boxes[_id] = nil
    broadcast(COOPBoombox.CMD_GONE, { id = _id })
    COOP.log("boombox: " .. tostring(box.name) .. " stopped (" .. tostring(_why) .. ")")
end

local function refuse(_player, _reason)
    tell(_player, COOPBoombox.CMD_RESULT, { reason = _reason })
end

-- The boombox the command is about, which has to be in the sender's hands.
local function heldItem(_player, _args)
    local id = tonumber(_args and _args.item)
    if id == nil then return nil end
    if not COOPBoombox.holds(_player, id) then return nil end
    return id
end

function COOPBoomboxServer.play(_player, _args)
    local id = heldItem(_player, _args)
    if id == nil then return refuse(_player, "hands") end
    local url = COOPBoombox.cleanUrl(_args.url)
    if url == nil then return refuse(_player, "url") end

    local box = boxes[id]
    local volume = box and box.volume or COOPBoombox.clampVolume(_args.volume)
    box = {
        id = id,
        holder = COOPBoombox.playerKey(_player),
        name = COOP.playerName(_player),
        url = url,
        volume = volume,
        paused = false,
        pos = 0,
        since = now(),
    }
    boxes[id] = box
    COOP.log("boombox: " .. box.name .. " plays " .. url)
    changed(box)
end

function COOPBoomboxServer.stop(_player, _args)
    local id = heldItem(_player, _args)
    if id == nil then return end
    silence(id, "turned off")
end

function COOPBoomboxServer.pause(_player, _args)
    local id = heldItem(_player, _args)
    local box = id and boxes[id]
    if box == nil then return end
    local paused = _args.paused == true
    if paused == box.paused then return end
    box.pos = positionOf(box)
    box.since = now()
    box.paused = paused
    changed(box)
end

function COOPBoomboxServer.volume(_player, _args)
    local id = heldItem(_player, _args)
    local box = id and boxes[id]
    if box == nil then return end
    box.volume = COOPBoombox.clampVolume(_args.volume)
    changed(box)
end

-- The holder's speaker has opened the link and knows its title and length. Taken only
-- from the holder, and only for the link still playing.
function COOPBoomboxServer.meta(_player, _args)
    local id = heldItem(_player, _args)
    local box = id and boxes[id]
    if box == nil or _args.url ~= box.url then return end
    local title = COOPBoombox.cleanTitle(_args.title)
    local duration = tonumber(_args.duration)
    if duration ~= nil and (duration ~= duration or duration <= 0) then duration = nil end
    if title == box.title and duration == box.duration then return end
    box.title = title
    box.duration = duration
    changed(box)
end

function COOPBoomboxServer.sync(_player)
    local list = {}
    for _, box in pairs(boxes) do table.insert(list, payload(box)) end
    tell(_player, COOPBoombox.CMD_ALL, { boxes = list })
end

function COOPBoomboxServer.handle(_player, _command, _args)
    if _player == nil then return end
    if not COOPBoombox.isEnabled() then return end
    _args = _args or {}
    if _command == COOPBoombox.CMD_PLAY then
        COOPBoomboxServer.play(_player, _args)
    elseif _command == COOPBoombox.CMD_STOP then
        COOPBoomboxServer.stop(_player, _args)
    elseif _command == COOPBoombox.CMD_PAUSE then
        COOPBoomboxServer.pause(_player, _args)
    elseif _command == COOPBoombox.CMD_VOLUME then
        COOPBoomboxServer.volume(_player, _args)
    elseif _command == COOPBoombox.CMD_META then
        COOPBoomboxServer.meta(_player, _args)
    elseif _command == COOPBoombox.CMD_SYNC then
        COOPBoomboxServer.sync(_player)
    end
end

local function onClientCommand(_module, _command, _player, _args)
    if _module ~= COOPBoombox.MODULE then return end
    COOPBoomboxServer.handle(_player, _command, _args)
end

Events.OnClientCommand.Add(onClientCommand)

-- ---------------------------------------------------------------------------
-- once a second: still in the hands? still playing? and the zombies
-- ---------------------------------------------------------------------------

-- A boombox is as loud to the dead as to the living. The same call vanilla's radios and
-- TVs make (WorldSoundManager), with the reach the music has for players.
local function makeNoise(_box, _holder)
    local volume = COOPBoombox.clampVolume(_box.volume)
    if _box.paused or volume <= 0 then return end
    local radius = math.floor(COOPBoombox.maxRange() * (0.3 + 0.7 * volume))
    pcall(function()
        addSound(_holder, math.floor(_holder:getX()), math.floor(_holder:getY()),
                math.floor(_holder:getZ()), radius, math.floor(radius * volume) + 10)
    end)
end

local function onTick()
    local t = now()
    if t - lastCheck < CHECK_MS then return end
    lastCheck = t
    if next(boxes) == nil then return end

    if not COOPBoombox.isEnabled() then
        for id in pairs(boxes) do silence(id, "feature off") end
        return
    end

    local noise = COOPBoombox.attractsZombies() and t - lastNoise >= NOISE_MS
    if noise then lastNoise = t end

    local ids = {}
    for id in pairs(boxes) do table.insert(ids, id) end
    for _, id in ipairs(ids) do
        local box = boxes[id]
        local holder = COOPBoombox.playerFor(box.holder)
        if holder == nil or holder:isDead() then
            silence(id, "holder gone")
        elseif not COOPBoombox.holds(holder, id) then
            silence(id, "not in the hands")
        elseif box.duration ~= nil and not box.paused and positionOf(box) > box.duration + 2 then
            silence(id, "track over")
        elseif noise then
            makeNoise(box, holder)
        end
    end
end

Events.OnTick.Add(onTick)
