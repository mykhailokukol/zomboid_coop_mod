--
-- CO-OP / Books at home - inventory check mark.
--
-- Vanilla draws one green tick on literature the player has read and on recordings
-- they have watched. We reuse that same slot for anything that is at home, swapping
-- the texture at draw time:
--
--   green tick  = already read   (vanilla behaviour, untouched)
--   white tick  = at home, not read yet
--
-- Read wins when both are true, so nothing the player relies on disappears.
--

if isServer() then return end

require "BAH_Common"
require "BAH_Catalog"

local VANILLA_TICK = "media/ui/Tick_Mark-10.png"
local WHITE_TICK = "media/ui/BAH_Tick_White.png"

local vanillaTick = nil
local whiteTick = nil
local patched = false

local function isVanillaTick(_texture)
    if _texture == nil then return false end
    if vanillaTick == nil then vanillaTick = getTexture(VANILLA_TICK) end
    if _texture == vanillaTick then return true end
    -- Identity should hold (textures are cached by path), but fall back on the name.
    local ok, name = pcall(function() return _texture:getName() end)
    return ok and name ~= nil and string.find(tostring(name), "Tick_Mark", 1, true) ~= nil
end

local function patch()
    if patched or ISInventoryPane == nil then return end
    patched = true

    local originalIsLiteratureRead = ISInventoryPane.isLiteratureRead
    local originalDrawTexture = ISInventoryPane.drawTexture

    -- Called by the pane immediately before it decides to draw the tick.
    function ISInventoryPane:isLiteratureRead(_playerObj, _item)
        self.bahWhiteTick = false

        if originalIsLiteratureRead(self, _playerObj, _item) then return true end
        if not COOP.featureEnabled(COOP.F_BOOKS) then return false end
        if _item == nil or _playerObj == nil then return false end

        -- Books and magazines by item type, VHS tapes by the recording they hold.
        local key = BAH.keyForItem(_item)
        if key == nil then return false end

        -- Let the vanilla "seen / heard / map read" cases keep their green tick.
        local ok, seen = pcall(function()
            return _item:hasBeenSeen(_playerObj) or _item:hasBeenHeard(_playerObj)
                    or _playerObj:hasReadMap(_item)
        end)
        if ok and seen then return false end

        if BooksAtHome == nil or not BooksAtHome.isMarked(key) then return false end

        self.bahWhiteTick = true
        return true
    end

    function ISInventoryPane:drawTexture(_texture, ...)
        if self.bahWhiteTick and isVanillaTick(_texture) then
            self.bahWhiteTick = false
            if whiteTick == nil then whiteTick = getTexture(WHITE_TICK) end
            return originalDrawTexture(self, whiteTick, ...)
        end
        return originalDrawTexture(self, _texture, ...)
    end

    BAH.log("inventory check mark hooked")
end

patch()
Events.OnGameBoot.Add(patch)
