--
-- CO-OP - the cart, on a multiplayer server: keeping carts' containers parentless.
--
-- The one thing about carts the server has to do itself. When a client reports the
-- pulled model, GameCharacterAttachedItemPacket.processServer calls setAttachedItem on
-- the server's copy of the player, and setAttachedItem makes the player the parent of
-- the cart's container (see COOPCart.clearParent for why that sends everything put in
-- the cart to the main inventory instead). There is no Lua event for that packet, so
-- every tick the worn carts of the players online are checked, and so is every cart
-- that was worn a tick ago - the one just parked keeps the parent otherwise, and then
-- the cart on the ground swallows items into its last puller's inventory.
--
-- A handful of players and one worn-items loop each: nothing worth throttling, and a
-- throttle would leave a window in which a transfer lands in the wrong place.
--
-- Single player needs none of this - its only copy of the cart is the client's, which
-- COOP_CartUI fixes the moment it attaches the model.
--

if not isServer() then return end

require "COOP_Cart"

COOPCartServer = COOPCartServer or {}

local worn = {}             -- item id -> the cart item, for carts worn last tick

local function onTick()
    if not COOPCart.isEnabled() then return end

    local players = getOnlinePlayers()
    if players == nil then return end

    local now = {}
    for i = 0, players:size() - 1 do
        local player = players:get(i)
        local cart = COOPCart.getWornCart(player)
        if cart ~= nil then
            local id = cart:getID()
            now[id] = cart
            if COOPCart.clearParent(cart) then
                COOPCart.trace("cleared the parent of %s worn by %s", COOPCart.describe(cart),
                        COOP.playerName(player))
            end
        end
    end

    for id, cart in pairs(worn) do
        if now[id] == nil and COOPCart.clearParent(cart) then
            COOPCart.trace("cleared the parent of %s, no longer worn", COOPCart.describe(cart))
        end
    end
    worn = now
end

Events.OnTick.Add(onTick)
