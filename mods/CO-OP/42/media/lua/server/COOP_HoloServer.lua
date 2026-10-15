--
-- CO-OP - authority over the holograms.
--
-- Runs on the dedicated/hosted server, and also in single player where there is no
-- server process (the client calls these functions directly).
--
-- "Something was built on it" has no event to hang on: OnObjectAdded and
-- OnTileObjectAdded fire only on clients, from the packets that carry a new object to
-- them, and never in single player. So the server looks instead. Each hologram keeps how
-- many objects stood on each of its squares when it was placed; once a second, every
-- hologram whose squares are loaded is counted again, and one more object on any square
-- removes it. A count is used rather than sprite names because a door or a curtain
-- changes its sprite when it opens.
--

if isClient() then return end

require "COOP_Holo"

COOPHoloServer = {}

local writeBudget = {}

local CHECK_EVERY_MS = 1000

local function ensureData()
    local data = ModData.getOrCreate(COOPHolo.MODDATA_KEY)
    if data.version == nil then data.version = COOPHolo.SCHEMA end
    if data.entries == nil then data.entries = {} end
    if data.nextId == nil then data.nextId = 1 end
    return data
end

-- What clients get: everything but the per-square counts, which only the server reads.
local function public(_entry)
    return {
        id = _entry.id, name = _entry.name, nSprite = _entry.nSprite,
        x = _entry.x, y = _entry.y, z = _entry.z, tiles = _entry.tiles, by = _entry.by,
    }
end

local function broadcast(_id, _entry)
    if not isServer() then return end
    sendServerCommand(COOPHolo.MODULE, COOPHolo.CMD_DELTA, {
        id = _id,
        entry = _entry and public(_entry) or nil,
        removed = _entry == nil,
    })
end

local function rateLimited(_playerObj)
    local key = COOP.playerName(_playerObj)
    local now = getTimestampMs()
    local budget = writeBudget[key]

    if budget == nil or now - budget.start > COOPHolo.WRITE_WINDOW_MS then
        writeBudget[key] = { start = now, count = 1 }
        return false
    end

    budget.count = budget.count + 1
    return budget.count > COOPHolo.WRITE_LIMIT
end

-- Objects that come and go without anybody building anything: dropped items, fire,
-- grass and trees.
local function counts(_object)
    if instanceof(_object, "IsoWorldInventoryObject") then return false end
    if instanceof(_object, "IsoFire") then return false end
    local ok, natural = pcall(function()
        if _object:getType() == IsoObjectType.tree then return true end
        local props = _object:getProperties()
        return props ~= nil and props:has(IsoFlagType.vegitation)
    end)
    return not (ok and natural)
end

local function objectCount(_square)
    if _square == nil then return 0 end
    local objects = _square:getObjects()
    local n = 0
    for i = 0, objects:size() - 1 do
        if counts(objects:get(i)) then n = n + 1 end
    end
    return n
end

-- Counts for every square of a hologram, or nil while its own square is not loaded. A
-- square above it that does not exist yet has nothing on it.
local function countTiles(_entry)
    local cell = getCell()
    if cell == nil or cell:getGridSquare(_entry.x, _entry.y, _entry.z) == nil then return nil end
    local result = {}
    for _, tile in ipairs(_entry.tiles) do
        result[COOPHolo.tileKey(tile.x, tile.y, tile.z)] = objectCount(cell:getGridSquare(tile.x, tile.y, tile.z))
    end
    return result
end

function COOPHoloServer.getEntries()
    return ensureData().entries
end

function COOPHoloServer.add(_playerObj, _name, _nSprite, _x, _y, _z)
    local x, y, z, nSprite = tonumber(_x), tonumber(_y), tonumber(_z), tonumber(_nSprite)
    if type(_name) ~= "string" or x == nil or y == nil or z == nil or nSprite == nil then return false end
    x, y, z, nSprite = math.floor(x), math.floor(y), math.floor(z), math.floor(nSprite)
    if nSprite < 1 or nSprite > 4 then return false end
    if rateLimited(_playerObj) then return false end

    local tiles = COOPHolo.tilesFor(_name, nSprite, x, y, z)
    if tiles == nil then
        COOP.log("hologram refused: no object " .. tostring(_name) .. " facing " .. nSprite)
        return false
    end

    local data = ensureData()
    local total = 0
    for _, entry in pairs(data.entries) do
        total = total + 1
        if entry.name == _name and entry.nSprite == nSprite and entry.x == x and entry.y == y and entry.z == z then
            return false
        end
    end
    if total >= COOPHolo.MAX_ENTRIES then
        COOP.log("hologram list is full, refusing another")
        return false
    end

    local id = tostring(data.nextId)
    data.nextId = data.nextId + 1

    local entry = {
        id = id, name = _name, nSprite = nSprite, x = x, y = y, z = z,
        tiles = tiles, by = COOP.playerName(_playerObj),
    }
    entry.counts = countTiles(entry)
    data.entries[id] = entry

    broadcast(id, entry)
    COOP.log(entry.by .. " placed hologram #" .. id .. " " .. _name .. " at " .. COOPHolo.tileKey(x, y, z))
    return true
end

local function drop(_data, _id, _why)
    _data.entries[_id] = nil
    broadcast(_id, nil)
    COOP.log("hologram #" .. _id .. " removed: " .. _why)
end

function COOPHoloServer.remove(_playerObj, _id)
    local id = COOPHolo.cleanId(_id)
    if id == nil then return false end
    local data = ensureData()
    if data.entries[id] == nil then return false end
    if rateLimited(_playerObj) then return false end
    drop(data, id, "deleted by " .. COOP.playerName(_playerObj))
    return true
end

-- One more object on any square than when it was placed removes the hologram. One
-- fewer lowers the count kept, so a thing taken away and then put back is noticed too.
local function check()
    local data = ensureData()
    local gone = {}
    for id, entry in pairs(data.entries) do
        local now = countTiles(entry)
        if now ~= nil then
            if entry.counts == nil then
                -- placed while its squares were not loaded on the server
                entry.counts = now
            else
                for key, n in pairs(now) do
                    local before = entry.counts[key] or 0
                    if n > before then
                        table.insert(gone, id)
                        break
                    elseif n < before then
                        entry.counts[key] = n
                    end
                end
            end
        end
    end
    for _, id in ipairs(gone) do drop(data, id, "something was built on it") end
end

local nextCheckMs = 0

local function onTick()
    if not COOPHolo.isEnabled() then return end
    local now = getTimestampMs()
    if now < nextCheckMs then return end
    nextCheckMs = now + CHECK_EVERY_MS
    local ok, err = pcall(check)
    if not ok then COOP.log("hologram check failed: " .. tostring(err)) end
end

local function sendSync(_playerObj)
    if not isServer() then return end
    local entries = {}
    for id, entry in pairs(ensureData().entries) do entries[id] = public(entry) end
    sendServerCommand(_playerObj, COOPHolo.MODULE, COOPHolo.CMD_SYNC, { entries = entries })
end

local function onClientCommand(_module, _command, _playerObj, _args)
    if _module ~= COOPHolo.MODULE then return end
    if not COOPHolo.isEnabled() then return end
    _args = _args or {}

    if _command == COOPHolo.CMD_SYNC_REQUEST then
        sendSync(_playerObj)
    elseif _command == COOPHolo.CMD_ADD then
        COOPHoloServer.add(_playerObj, _args.name, _args.nSprite, _args.x, _args.y, _args.z)
    elseif _command == COOPHolo.CMD_REMOVE then
        COOPHoloServer.remove(_playerObj, _args.id)
    end
end

Events.OnClientCommand.Add(onClientCommand)
Events.OnTick.Add(onTick)

Events.OnInitGlobalModData.Add(function()
    ensureData()
    COOP.log("holograms ready")
end)
