--
-- CO-OP - authority over what the concrete mixer produces.
--
-- The mixer's two containers belong to the server, so a client asks and the server
-- mixes. Single player calls COOPMixer.craft directly - there is no server there and
-- the client already holds the authoritative object.
--

if isClient() then return end

require "COOP_Mixer"

COOPMixerServer = {}

local WRITE_WINDOW_MS = 2000
local WRITE_LIMIT = 10

local writeBudget = {}

-- Same shape as the books and to-do lists: a burst is fine, a flood is not.
local function rateLimited(_playerObj)
    local key = COOP.playerName(_playerObj)
    local now = getTimestampMs()
    local budget = writeBudget[key]

    if budget == nil or now - budget.start > WRITE_WINDOW_MS then
        writeBudget[key] = { start = now, count = 1 }
        return false
    end

    budget.count = budget.count + 1
    return budget.count > WRITE_LIMIT
end

-- The mixer the player says they are standing at, or nil if that story does not hold up.
local function mixerFor(_playerObj, _args)
    local x = tonumber(_args.x)
    local y = tonumber(_args.y)
    local z = tonumber(_args.z)
    if x == nil or y == nil or z == nil then return nil end

    -- Distance is checked server-side for the same reason the ping cooldown is: a
    -- client must not be able to work a mixer on the other side of the map.
    if math.abs(_playerObj:getX() - x) > COOPMixer.REACH + 1
            or math.abs(_playerObj:getY() - y) > COOPMixer.REACH + 1 then
        return nil
    end

    local square = getCell() and getCell():getGridSquare(x, y, z) or nil
    return COOPMixer.findOnSquare(square)
end

function COOPMixerServer.craft(_playerObj, _args)
    if not COOPMixer.isEnabled() then return false end
    if _playerObj == nil or _args == nil then return false end
    if rateLimited(_playerObj) then return false end

    local recipe = COOPMixer.recipeById(_args.recipe)
    if recipe == nil then return false end

    local mixer = mixerFor(_playerObj, _args)
    if mixer == nil then return false end

    if not COOPMixer.craft(mixer, recipe) then return false end

    COOP.log(COOP.playerName(_playerObj) .. " mixed " .. recipe.id
            .. " at " .. tostring(_args.x) .. "," .. tostring(_args.y))
    return true
end

-- Somebody opened a mixer: note where it is so the rain keeps it topped up.
function COOPMixerServer.seen(_playerObj, _args)
    if not COOPMixer.isEnabled() then return end
    if _playerObj == nil or _args == nil then return end

    local mixer = mixerFor(_playerObj, _args)
    if mixer == nil then return end

    COOPMixer.prepare(mixer)
end

local function onClientCommand(_module, _command, _playerObj, _args)
    if _module ~= COOPMixer.MODULE then return end

    if _command == COOPMixer.CMD_CRAFT then
        COOPMixerServer.craft(_playerObj, _args)
    elseif _command == COOPMixer.CMD_SEEN then
        COOPMixerServer.seen(_playerObj, _args)
    end
end

Events.OnClientCommand.Add(onClientCommand)
