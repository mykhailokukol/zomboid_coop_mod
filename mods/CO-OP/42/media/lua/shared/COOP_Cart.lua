--
-- CO-OP - the cart: a container you pull behind you.
--
-- Valheim's cart, as far as Project Zomboid lets it go. It is built at a workbench out
-- of planks, nails and two matching tires, worn in a slot of its own next to any
-- backpack, and pulled along behind the player; parked, it is an item on the ground
-- anyone can open.
--
-- ---------------------------------------------------------------------------
-- Why it is a bag and not a vehicle
-- ---------------------------------------------------------------------------
--
-- A vehicle part could hold as much as we liked, but a vehicle has Bullet collision: it
-- would shove players and zombies about, stick on fences and never fit through a door.
-- An item has none of that, goes indoors, and reaches every other player through the
-- engine's own item and worn-item sync. The price is the engine's limits on item
-- containers, read out of projectzomboid.jar:
--
--   ItemContainer.getCapacity()       min(capacity, 50) for any container in an item
--   ItemContainer.hasRoomFor()        a container lying on the ground also has to fit
--                                     in the 50 kg a floor square takes, load included
--
-- So the cart holds 50 kg (the cart itself weighs nothing, so that is 50 parked too, on
-- a square with nothing else on it), and the Organization skill cannot raise it - there
-- is no higher number for it to set.
--
-- The slot it is worn in, coop:cart, is registered in media/registries.lua - the only
-- place early enough for the item script to name it - and put in the Human body location
-- group below.
--
-- ---------------------------------------------------------------------------
-- What each half does
-- ---------------------------------------------------------------------------
--
-- This file is the model: what a cart is, how much it slows its puller, its body
-- location, and the one attached-item location the pulled model hangs from. Both
-- locations have to exist on the server as well, or it refuses the worn item and the
-- attached item the client reports.
--
-- Everything else runs on the pulling player's client, in client/COOP_CartUI.lua:
-- attaching and parking, the pulled model, the slowdown, and the things a cart stops you
-- doing. None of it needs a server half - the worn item, the attached model and the
-- transfers are all vanilla traffic, and the slowdown only has to hold on the machine
-- that moves the character.
--

require "COOP_Common"

COOPCart = COOPCart or {}

-- Traces every decision the cart code makes into console.txt (client) and
-- coop-console.txt (hosted server), each line starting "[CO-OP] cart:". On while the
-- feature is being tested in game; set false once it has settled. COOPCartUI.dump()
-- in the debug console prints the whole state on demand, whatever this is set to.
COOPCart.debug = true

COOPCart.ITEM = "COOP.Cart"

function COOPCart.trace(_fmt, ...)
    if not COOPCart.debug then return end
    local ok, text = pcall(string.format, _fmt, ...)
    if not ok then text = tostring(_fmt) end
    local side = isServer() and "server" or (isClient() and "client" or "sp")
    COOP.log("cart[" .. side .. "]: " .. text)
end

-- "Cart#123 (0.0kg, load 4.5kg in 7 items)" - enough to tell carts apart in the log.
function COOPCart.describe(_item)
    if _item == nil then return "nil" end
    local ok, text = pcall(function()
        local load, count = 0, 0
        pcall(function() load = _item:getInventory():getContentsWeight() end)
        pcall(function() count = _item:getInventory():getItems():size() end)
        return string.format("%s#%s (%.1fkg, load %.1fkg in %d items)", tostring(_item:getType()),
                tostring(_item:getID()), _item:getActualWeight(), load, count)
    end)
    if ok then return text end
    return tostring(_item)
end

-- The slowdown: 15% for every 20 kg of load, counted continuously, never past 75%.
-- The load is the real weight inside - the puller carries none of it (WeightReduction 100).
COOPCart.SLOW_PER_KG = 0.15 / 20.0
COOPCart.MAX_SLOW = 0.75

-- The vanilla speed scales of the three nodes the cart's animation nodes replace
-- (defaultWalk, defaultRun, defaultSprint). A cart slows them by its factor.
COOPCart.WALK_SCALE = 1.04
COOPCart.RUN_SCALE = 1.04
COOPCart.SPRINT_SCALE = 0.96

-- The attached-item location the pulled model hangs from, and the name of the body
-- model attachment it resolves to (added to FemaleBody/MaleBody by COOP_CartUI).
COOPCart.LOCATION = "COOP Cart"
COOPCart.ATTACHMENT = "coop_cart"

-- The body location the cart is worn in (media/registries.lua registers it).
COOPCart.BODY_LOCATION = "coop:cart"

function COOPCart.bodyLocation()
    local ok, location = pcall(function() return ItemBodyLocation.get(ResourceLocation.of(COOPCart.BODY_LOCATION)) end)
    if ok then return location end
    return nil
end

function COOPCart.isEnabled()
    return COOP.featureEnabled(COOP.F_CART)
end

function COOPCart.isCart(_item)
    if _item == nil then return false end
    local ok, fullType = pcall(function() return _item:getFullType() end)
    return ok and fullType == COOPCart.ITEM
end

-- True for the item container that is a cart's body.
function COOPCart.isCartContainer(_container)
    if _container == nil then return false end
    local ok, item = pcall(function() return _container:getContainingItem() end)
    return ok and COOPCart.isCart(item)
end

-- The cart this character is pulling, or nil.
function COOPCart.getWornCart(_character)
    if _character == nil then return nil end
    local ok, cart = pcall(function()
        local worn = _character:getWornItems()
        for i = 0, worn:size() - 1 do
            local item = worn:getItemByIndex(i)
            if COOPCart.isCart(item) then return item end
        end
        return nil
    end)
    if ok then return cart end
    return nil
end

-- Undoes what IsoGameCharacter.setAttachedItem does to a container item it is given:
--
--     invContainer.getInventory().parent = this;
--
-- A bag's own container normally has no parent (setWornItem only re-parents the
-- container the bag sits *in*). With the player as parent, ContainerID.set - how every
-- item transaction names its source and destination - takes the cart's container for
-- the player's main inventory: everything dropped into the cart lands in the inventory,
-- and the server, which runs the same setAttachedItem when it relays the model, reports
-- the cart's contents back as main-inventory items too. So after every attach, on both
-- sides, the parent goes back to nil. Returns true when it had to.
function COOPCart.clearParent(_cart)
    if _cart == nil then return false end
    local ok, changed = pcall(function()
        local inventory = _cart:getInventory()
        if inventory ~= nil and inventory:getParent() ~= nil then
            inventory:setParent(nil)
            return true
        end
        return false
    end)
    return ok and changed == true
end

-- Kilograms inside the cart - the real weight, not the reduced one its puller feels.
function COOPCart.loadWeight(_cart)
    if _cart == nil then return 0 end
    local ok, weight = pcall(function() return _cart:getInventory():getContentsWeight() end)
    if ok and weight ~= nil then return weight end
    return 0
end

-- Movement speed multiplier for a cart carrying _load kilograms, 1.0 down to 0.25.
function COOPCart.speedFactor(_load)
    local slow = (_load or 0) * COOPCart.SLOW_PER_KG
    if slow < 0 then slow = 0 end
    if slow > COOPCart.MAX_SLOW then slow = COOPCart.MAX_SLOW end
    return 1.0 - slow
end

-- ---------------------------------------------------------------------------
-- the attached-item location
--
-- Declared the same way media/lua/shared/NPCs/AttachedLocations.lua declares the belt
-- and back slots, at load, on both sides. getOrCreateLocation is idempotent, so a Lua
-- reload does no harm.
-- ---------------------------------------------------------------------------

local function declareLocation()
    local ok, err = pcall(function()
        local group = AttachedLocations.getGroup("Human")
        group:getOrCreateLocation(COOPCart.LOCATION):setAttachmentName(COOPCart.ATTACHMENT)
    end)
    if ok then
        COOPCart.trace("attached location '%s' -> attachment '%s' declared", COOPCart.LOCATION, COOPCart.ATTACHMENT)
    else
        COOP.log("cart: could not declare the attached location: " .. tostring(err))
    end
end

declareLocation()

-- The worn slot. WornItems.setItem looks the location up in the character's body
-- location group, so a registered id that is not in the group cannot be worn. Nothing
-- is exclusive with it: a cart goes with a backpack, a fanny pack, anything.
local function declareBodyLocation()
    local ok, err = pcall(function()
        local location = COOPCart.bodyLocation()
        if location == nil then
            error("'" .. COOPCart.BODY_LOCATION .. "' is not registered - is media/registries.lua in the mod?")
        end
        BodyLocations.getGroup("Human"):getOrCreateLocation(location)
    end)
    if ok then
        COOPCart.trace("body location '%s' is in the Human group", COOPCart.BODY_LOCATION)
    else
        COOP.log("cart: could not declare the body location: " .. tostring(err))
    end
end

declareBodyLocation()
