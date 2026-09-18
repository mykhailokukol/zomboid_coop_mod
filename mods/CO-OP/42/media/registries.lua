--
-- CO-OP - things the engine has to know before it reads the item scripts.
--
-- Build 42 runs every mod's media/registries.lua from Core (ModRegistries.init) right
-- before ScriptManager.Load(), on the client and on the server alike. That makes this
-- the one place a new body location can be registered in time for an item script to
-- name it.
--
-- coop:cart is the cart's own slot (COOP_Cart.lua, scripts/coop_cart.txt), so pulling
-- a cart leaves the back free for a backpack. Registering the same id twice throws,
-- and a registry reset only clears non-base ids, hence the check.
--

local CART = "coop:cart"

if ItemBodyLocation.get(ResourceLocation.of(CART)) == nil then
    ItemBodyLocation.register(CART)
end
