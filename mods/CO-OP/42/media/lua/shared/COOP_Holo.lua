--
-- CO-OP - holograms: a plan of a build, left in the world for everyone to see.
--
-- "Build Hologram" in the Build window places the selected recipe as a light-blue ghost
-- instead of building it. A hologram is not an object: nothing collides with it and
-- nothing is saved on its squares. It is a line in a server-owned list (GlobalModData,
-- same shape as the to-do list), drawn by every client with the build cursor's own
-- ghost-tile call.
--
-- It goes away when anybody deletes it from its right-click menu, or when something is
-- built or placed on one of its squares - including the real thing.
--

require "COOP_Common"

COOPHolo = COOPHolo or {}

COOPHolo.MODULE = "CO-OP"
COOPHolo.MODDATA_KEY = "COOP_Holo"
COOPHolo.SCHEMA = 1

COOPHolo.MAX_ENTRIES = 500       -- across the whole server
COOPHolo.MAX_TILES = 32          -- squares one hologram may cover
COOPHolo.WRITE_WINDOW_MS = 2000  -- rate limit window, per player
COOPHolo.WRITE_LIMIT = 20        -- writes allowed inside that window

COOPHolo.CMD_SYNC_REQUEST = "holoRequestSync"
COOPHolo.CMD_SYNC = "holoSync"
COOPHolo.CMD_DELTA = "holoDelta"
COOPHolo.CMD_ADD = "holoAdd"
COOPHolo.CMD_REMOVE = "holoRemove"

-- light blue, see-through
COOPHolo.R, COOPHolo.G, COOPHolo.B, COOPHolo.A = 0.45, 0.8, 1.0, 0.5

function COOPHolo.isEnabled()
    return COOP.featureEnabled(COOP.F_HOLO)
end

function COOPHolo.cleanId(_id)
    if _id == nil then return nil end
    local id = tostring(_id)
    if not string.match(id, "^%d+$") then return nil end
    return id
end

function COOPHolo.tileKey(_x, _y, _z)
    return _x .. "," .. _y .. "," .. _z
end

-- nSprite is the build cursor's rotation: 1..4 for W, N, E, S. The object info numbers
-- its faces N, W, S, E from zero - the same conversion ISBuildIsoEntity:getFace does.
function COOPHolo.faceFor(_info, _nSprite)
    local index = _nSprite
    if index == 2 then index = 0 elseif index == 4 then index = 2 end
    return _info:getFace(index)
end

-- The squares a recipe's object covers when its cursor stands at x,y,z with this
-- rotation, and the sprite drawn on each: { {x=, y=, z=, s=}, ... }. nil when the name
-- or rotation does not exist. Both sides work it out, so the server never takes a
-- client's word for which squares a hologram covers.
function COOPHolo.tilesFor(_name, _nSprite, _x, _y, _z)
    local ok, tiles = pcall(function()
        local info = SpriteConfigManager.GetObjectInfo(_name)
        if info == nil then return nil end
        local face = COOPHolo.faceFor(info, _nSprite)
        if face == nil then return nil end

        local list = {}
        for zz = 0, face:getzLayers() - 1 do
            for xx = 0, face:getWidth() - 1 do
                for yy = 0, face:getHeight() - 1 do
                    local tileInfo = face:getTileInfo(xx, yy, zz)
                    local sprite = tileInfo and tileInfo:getSpriteName()
                    if sprite then
                        table.insert(list, { x = _x + xx, y = _y + yy, z = _z + zz, s = sprite })
                    end
                end
            end
        end
        return list
    end)
    if not ok or tiles == nil or #tiles == 0 or #tiles > COOPHolo.MAX_TILES then return nil end
    return tiles
end

-- The recipe's name as the Build window shows it.
function COOPHolo.displayName(_name)
    local ok, text = pcall(function()
        local info = SpriteConfigManager.GetObjectInfo(_name)
        return info:getRecipe():getCraftRecipe():getTranslationName()
    end)
    if ok and text ~= nil and text ~= "" then return tostring(text) end
    return tostring(_name)
end
