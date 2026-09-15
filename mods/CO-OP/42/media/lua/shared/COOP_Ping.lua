--
-- CO-OP - map and world pings.
--
-- Middle-click anywhere - on the open world map, or on the ground, an item or a
-- building - and everyone on the server sees a marker there for a few seconds.
--
--   Client                              Server
--   ------                              ------
--   middle click --------------------►  OnClientCommand("CO-OP", "ping")
--                                         validate, rate limit, stamp the sender
--   marker + arrow + label  ◄----------  sendServerCommand(all, "ping")
--
-- Clients never invent a ping for anyone else: the server is what turns "I clicked
-- here" into "PlayerName pinged here", so a client cannot spoof another player or
-- spam the channel. In single player the client shows its own ping directly.
--

require "COOP_Common"

COOPPing = COOPPing or {}

COOPPing.MODULE = "CO-OP"
COOPPing.COMMAND = "ping"

-- Defaults for how long a ping stays up and how often one player may place one. The
-- sandbox options override both; these are what the mod used before they existed.
COOPPing.DURATION_MS = 12000
COOPPing.MIN_INTERVAL_MS = 1500

function COOPPing.durationMs()
    return COOP.numberOption("PingDuration", COOPPing.DURATION_MS / 1000, 3, 60) * 1000
end

function COOPPing.intervalMs()
    return COOP.numberOption("PingCooldown", COOPPing.MIN_INTERVAL_MS / 1000, 0.5, 10) * 1000
end

-- Levels the world has; anything outside this is a malformed or hostile payload.
COOPPing.MIN_Z = 0
COOPPing.MAX_Z = 8

-- What was under the cursor. The clicking client works this out - it is the only one
-- holding the mouse - and the server checks it against this list before passing it on,
-- so a crafted payload cannot make everyone draw something that does not exist.
COOPPing.SPOT = "spot"
COOPPing.DANGER = "danger"
COOPPing.PLAYER = "player"
COOPPing.VEHICLE = "vehicle"
COOPPing.LOOT = "loot"
COOPPing.BODY = "body"

COOPPing.KINDS = {
    [COOPPing.SPOT] = true,
    [COOPPing.DANGER] = true,
    [COOPPing.PLAYER] = true,
    [COOPPing.VEHICLE] = true,
    [COOPPing.LOOT] = true,
    [COOPPing.BODY] = true,
}

-- ---------------------------------------------------------------------------
-- the payload
-- ---------------------------------------------------------------------------

local function number(_value)
    local n = tonumber(_value)
    -- rejects nil, strings, and the NaN/inf a crafted payload could carry
    if n == nil or n ~= n or n == math.huge or n == -math.huge then return nil end
    return n
end

-- Returns floored x, y, z and the kind, or nil when the payload cannot be trusted.
function COOPPing.sanitise(_args)
    if _args == nil then return nil end

    local x = number(_args.x)
    local y = number(_args.y)
    local z = number(_args.z) or 0
    if x == nil or y == nil then return nil end

    z = math.floor(z)
    if z < COOPPing.MIN_Z then z = COOPPing.MIN_Z end
    if z > COOPPing.MAX_Z then z = COOPPing.MAX_Z end

    local kind = _args.kind
    if kind == nil or COOPPing.KINDS[kind] ~= true then kind = COOPPing.SPOT end

    return math.floor(x), math.floor(y), z, kind
end

-- ---------------------------------------------------------------------------
-- colour
-- ---------------------------------------------------------------------------

-- Derived from the name rather than from any per-player colour the engine keeps,
-- because every client has to paint the same player's ping the same way and a remote
-- player's chat colour is not something every client reliably knows.
local function hash(_text)
    local h = 5381
    for i = 1, #_text do
        h = (h * 33 + string.byte(_text, i)) % 16777216
    end
    return h
end

local function hueToRgb(_hue)
    local h = (_hue % 1) * 6
    local x = 1 - math.abs(h % 2 - 1)
    if h < 1 then return 1, x, 0 end
    if h < 2 then return x, 1, 0 end
    if h < 3 then return 0, 1, x end
    if h < 4 then return 0, x, 1 end
    if h < 5 then return x, 0, 1 end
    return 1, 0, x
end

function COOPPing.colourFor(_name)
    local text = tostring(_name or "?")
    local r, g, b = hueToRgb((hash(text) % 360) / 360)
    -- lift it towards white: a pure hue like (0,0,1) is too dark to read on the map
    return 0.35 + r * 0.65, 0.35 + g * 0.65, 0.35 + b * 0.65
end

-- ---------------------------------------------------------------------------
-- the server
-- ---------------------------------------------------------------------------

local lastPing = {}

local function onClientCommand(_module, _command, _playerObj, _args)
    if _module ~= COOPPing.MODULE or _command ~= COOPPing.COMMAND then return end
    if _playerObj == nil then return end
    if not COOP.featureEnabled(COOP.F_PINGS) then return end

    local x, y, z, kind = COOPPing.sanitise(_args)
    if x == nil then return end

    local name = COOP.playerName(_playerObj)
    if name == "?" then return end

    local now = getTimestampMs()
    local last = lastPing[name]
    if last ~= nil and now - last < COOPPing.intervalMs() then return end
    lastPing[name] = now

    COOP.log("ping from " .. name .. " at " .. x .. "," .. y .. "," .. z .. " (" .. kind .. ")")
    sendServerCommand(COOPPing.MODULE, COOPPing.COMMAND,
            { x = x, y = y, z = z, kind = kind, by = name })
end

if isServer() then
    Events.OnClientCommand.Add(onClientCommand)
end
