--
-- CO-OP - the cart, on the client: attaching and parking it, the model behind the
-- player, the slowdown, and what a cart will not let you do.
--
-- The rules and the reasons they look the way they do are in shared/COOP_Cart.lua.
-- Everything here runs for the local player only and none of it is a new network
-- message: attaching is a vanilla transfer plus a vanilla wear, parking is a vanilla
-- drop, the model is a vanilla attached item (IsoGameCharacter.setAttachedItem sends it
-- to the server itself), and the slowdown is an animation variable on the one machine
-- that moves this character.
--
-- With COOPCart.debug on, every decision below is traced to console.txt as
-- "[CO-OP] cart[client]: ...". COOPCartUI.dump() prints the full state at any time.
--

if isServer() then return end

require "COOP_Cart"
require "TimedActions/ISBaseTimedAction"

COOPCartUI = COOPCartUI or {}

local trace = COOPCart.trace
local describe = COOPCart.describe

-- ---------------------------------------------------------------------------
-- the pulled model
--
-- Where the trailer mesh sits relative to Bip01_Pelvis. In that bone's space +x is up
-- the spine, y is left/right and +z is forward (read off the vanilla belt attachments:
-- knife_belt_back sits at z -0.08, knife_belt_front at z +0.05), in metres.
--
-- These are first guesses and only the game can say if they are right. Tune them live
-- from the debug console, e.g.
--
--     COOPCartUI.tune(-0.55, 0, -0.9, 0, 0, -90, 1.0)
--
-- then copy the numbers that look right back here.
-- ---------------------------------------------------------------------------

COOPCartUI.BONE = "Bip01_Pelvis"
-- x -0.55 puts the wheels on the ground. -0.86, which allowed for the model's origin
-- having moved to the bottom of the wheels, sank it half into the ground (in game,
-- 2026-09-18).
COOPCartUI.OFFSET = { -0.55, 0.0, -0.90 }
-- z -90: at +90 the trailer was drawn upside down (seen in game, 2026-09-18).
COOPCartUI.ROTATE = { 0.0, 0.0, -90.0 }
COOPCartUI.SCALE = 1.0

COOPCartUI.BODY_MODELS = { "FemaleBody", "MaleBody" }

local CHECK_MS = 250        -- how often a local player's cart state is reconciled
local PENDING_MS = 20000    -- how long an attach may take to go from the floor to the back
local REDROP_MS = 5000      -- how long before a cart that did not drop is dropped again
local MESSAGE_MS = 1500     -- minimum gap between two "not with a cart" messages
local TRACE_REPEAT_MS = 2000 -- minimum gap between two identical block traces

local pending = {}          -- item id -> time until which it may enter the inventory
local detaching = {}        -- item id -> time until which its model is not put back
local dropQueued = {}       -- item id -> time until which it is not dropped again
local nextCheck = {}        -- player number -> time of the next reconcile
local animOn = {}           -- player number -> the COOPCart variable is set
local vaultOff = {}         -- player number -> we turned auto-vault off, so we turn it back on
local lastState = {}        -- player number -> last reconciled state, for change traces
local lastTrace = {}        -- trace key -> time it was last written
local lastMessage = 0

local function now() return getTimestampMs() end

-- A trace for things that can fire every frame (isValid runs repeatedly): each key at
-- most once per TRACE_REPEAT_MS.
local function traceOnce(_key, _fmt, ...)
    if not COOPCart.debug then return end
    local t = now()
    if lastTrace[_key] ~= nil and t - lastTrace[_key] < TRACE_REPEAT_MS then return end
    lastTrace[_key] = t
    trace(_fmt, ...)
end

local function containerName(_container)
    if _container == nil then return "nil" end
    local ok, text = pcall(function()
        local item = _container:getContainingItem()
        if item ~= nil then return _container:getType() .. " in " .. tostring(item:getType()) end
        local parent = _container:getParent()
        if instanceof(parent, "IsoPlayer") then return "inventory of " .. COOP.playerName(parent) end
        return _container:getType()
    end)
    if ok then return text end
    return tostring(_container)
end

local function applyAttachment(_attachment)
    _attachment:setBone(COOPCartUI.BONE)
    _attachment:getOffset():set(COOPCartUI.OFFSET[1], COOPCartUI.OFFSET[2], COOPCartUI.OFFSET[3])
    _attachment:getRotate():set(COOPCartUI.ROTATE[1], COOPCartUI.ROTATE[2], COOPCartUI.ROTATE[3])
    _attachment:setScale(COOPCartUI.SCALE)
end

local function attachmentText(_attachment)
    local ok, text = pcall(function()
        local o, r = _attachment:getOffset(), _attachment:getRotate()
        return string.format("bone %s offset %.3f %.3f %.3f rotate %.1f %.1f %.1f scale %.3f",
                tostring(_attachment:getBone()), o:x(), o:y(), o:z(), r:x(), r:y(), r:z(),
                _attachment:getScale())
    end)
    if ok then return text end
    return "?"
end

-- The attached-item location says "coop_cart"; this puts a coop_cart attachment on the
-- body models for it to resolve to. A mod script redefining FemaleBody would replace the
-- whole vanilla model, so it is added from here instead, the same as editing the model
-- in the attachment editor would. Idempotent, and cheap enough to call on every event
-- that might follow a script reload.
function COOPCartUI.ensureBodyAttachments(_why)
    local ok, err = pcall(function()
        for _, name in ipairs(COOPCartUI.BODY_MODELS) do
            local script = getScriptManager():getModelScript(name)
            if script == nil then
                trace("body attachment (%s): no model script '%s' yet", tostring(_why), name)
            elseif script:getAttachmentById(COOPCart.ATTACHMENT) == nil then
                local attachment = ModelAttachment.new(COOPCart.ATTACHMENT)
                applyAttachment(attachment)
                script:addAttachment(attachment)
                trace("body attachment (%s): added '%s' to %s - %s", tostring(_why),
                        COOPCart.ATTACHMENT, name, attachmentText(attachment))
            end
        end
    end)
    if not ok then COOP.log("cart: could not add the body attachment: " .. tostring(err)) end
end

-- Debug console helper: move the pulled model and redraw it on every local player.
function COOPCartUI.tune(_ox, _oy, _oz, _rx, _ry, _rz, _scale)
    COOPCartUI.OFFSET = { _ox or COOPCartUI.OFFSET[1], _oy or COOPCartUI.OFFSET[2], _oz or COOPCartUI.OFFSET[3] }
    COOPCartUI.ROTATE = { _rx or COOPCartUI.ROTATE[1], _ry or COOPCartUI.ROTATE[2], _rz or COOPCartUI.ROTATE[3] }
    COOPCartUI.SCALE = _scale or COOPCartUI.SCALE

    COOPCartUI.ensureBodyAttachments("tune")
    for _, name in ipairs(COOPCartUI.BODY_MODELS) do
        local script = getScriptManager():getModelScript(name)
        local attachment = script and script:getAttachmentById(COOPCart.ATTACHMENT)
        if attachment ~= nil then applyAttachment(attachment) end
    end

    -- the attached model instance is built once, so take the cart off and put it back
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        local cart = player and COOPCartUI.wornCart(player)
        if cart ~= nil then
            player:setAttachedItem(COOPCart.LOCATION, nil)
            player:setAttachedItem(COOPCart.LOCATION, cart)
            COOPCart.clearParent(cart)
            pcall(function() player:resetModelNextFrame() end)
        end
    end

    print(string.format("[CO-OP] cart model: offset %.3f %.3f %.3f  rotate %.1f %.1f %.1f  scale %.3f",
            COOPCartUI.OFFSET[1], COOPCartUI.OFFSET[2], COOPCartUI.OFFSET[3],
            COOPCartUI.ROTATE[1], COOPCartUI.ROTATE[2], COOPCartUI.ROTATE[3], COOPCartUI.SCALE))
end

-- ---------------------------------------------------------------------------
-- small helpers
-- ---------------------------------------------------------------------------

local function isPending(_item)
    local until_ = pending[_item:getID()]
    return until_ ~= nil and until_ > now()
end

local function pulling(_character)
    return _character ~= nil and COOPCart.isEnabled() and COOPCartUI.wornCart(_character) ~= nil
end

local function say(_character, _key)
    if now() - lastMessage < MESSAGE_MS then return end
    lastMessage = now()
    pcall(function() HaloTextHelper.addBadText(_character, getText(_key)) end)
end

local function backItem(_player)
    local ok, item = pcall(function() return _player:getWornItem(ItemBodyLocation.BACK) end)
    if ok then return item end
    return nil
end

local function cartSlotItem(_player)
    local location = COOPCart.bodyLocation()
    if location == nil then return nil end
    local ok, item = pcall(function() return _player:getWornItem(location) end)
    if ok then return item end
    return nil
end

-- ---------------------------------------------------------------------------
-- attaching and parking
-- ---------------------------------------------------------------------------

-- Why this player cannot attach that cart right now, as a translation key; nil if they can.
function COOPCartUI.attachProblem(_player, _item)
    if _player:getVehicle() ~= nil then return "ContextMenu_COOP_Cart_InVehicle" end
    if COOPCartUI.wornCart(_player) ~= nil then return "ContextMenu_COOP_Cart_AlreadyPulling" end
    if _item:getWorldItem() == nil then return "ContextMenu_COOP_Cart_NotParked" end
    return nil
end

-- Floor -> main inventory -> worn, as one queue. The transfer is the one move into the
-- inventory a cart is allowed to make, and only while it is pending (see the transfer
-- hook below). The cart has a slot of its own, so nothing else comes off.
function COOPCartUI.attach(_player, _item)
    trace("attach requested by %s: %s, in %s", COOP.playerName(_player), describe(_item),
            containerName(_item:getContainer()))

    local world = _item:getWorldItem()
    local square = world and world:getSquare()
    if square == nil then
        trace("attach refused: the cart has no world item / square")
        return
    end
    local problem = COOPCartUI.attachProblem(_player, _item)
    if problem ~= nil then
        trace("attach refused: %s", problem)
        return
    end
    if not luautils.walkAdj(_player, square) then
        trace("attach refused: cannot walk next to %d,%d,%d", square:getX(), square:getY(), square:getZ())
        return
    end

    pending[_item:getID()] = now() + PENDING_MS

    ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(
            _player, _item, _item:getContainer(), _player:getInventory()))
    ISTimedActionQueue.add(ISWearClothing:new(_player, _item))
    trace("attach queued: walk to %d,%d,%d, transfer to inventory, wear (pending %d ms)",
            square:getX(), square:getY(), square:getZ(), PENDING_MS)
end

-- Vanilla's drop does all of it: takes the model off, unwears the cart and puts it on
-- the floor where the player stands. The model comes off before the unwear finishes,
-- so reconcile is told not to put it back in the meantime.
function COOPCartUI.detach(_player, _cart)
    if _player == nil or _cart == nil then return end
    trace("detach requested by %s: %s at %d,%d,%d", COOP.playerName(_player), describe(_cart),
            math.floor(_player:getX()), math.floor(_player:getY()), math.floor(_player:getZ()))
    detaching[_cart:getID()] = now() + PENDING_MS
    ISInventoryPaneContextMenu.dropItem(_cart, _player:getPlayerNum())
end

-- ---------------------------------------------------------------------------
-- keeping one player's cart state right
--
-- Run a few times a second for each local player. Everything it does is a no-op when
-- nothing changed, so it is also what repairs things after a load, a Lua reload or a
-- vanilla action that moved the cart some way we did not plan for.
-- ---------------------------------------------------------------------------

local function setAnim(_player, _on)
    local index = _player:getPlayerNum()
    if not _on and not animOn[index] then return end
    if animOn[index] ~= _on then trace("anim variable COOPCart = %s", tostring(_on)) end
    animOn[index] = _on
    _player:setVariable("COOPCart", _on)
end

-- Running or sprinting into a low fence vaults it straight from Java
-- (IsoMovingObject.checkVaultOver), and the context-key hop goes through
-- IsoPlayer.doContextHopOverFence - neither is a timed action, so the isValid hooks never
-- see them. Both give up when the player's ignoreAutoVault is set, the switch the vanilla
-- tutorial uses to keep the player on its side of a fence: pulling a cart, the player
-- runs into a fence and stops, as into a wall. Only a flag this code set is cleared again.
local function setVaultBlocked(_player, _blocked)
    local index = _player:getPlayerNum()
    if _blocked then
        if not _player:isIgnoreAutoVault() then
            _player:setIgnoreAutoVault(true)
            vaultOff[index] = true
            trace("auto-vault over fences off while pulling")
        end
    elseif vaultOff[index] then
        _player:setIgnoreAutoVault(false)
        vaultOff[index] = nil
        trace("auto-vault over fences back on")
    end
end

local function sweepInventory(_player, _enabled)
    local carts = _player:getInventory():getAllTypeRecurse(COOPCart.ITEM)
    if carts == nil then return end
    for i = 0, carts:size() - 1 do
        local cart = carts:get(i)

        -- A cart is pulled or parked, never carried. One that reached the inventory
        -- some other way - crafted, unworn through the vanilla menu, loaded from an
        -- older save - goes to the floor as soon as the player is not busy.
        if _enabled and not _player:isEquippedClothing(cart) and not isPending(cart)
                and not _player:hasTimedActions() then
            local id = cart:getID()
            if dropQueued[id] == nil or dropQueued[id] < now() then
                dropQueued[id] = now() + REDROP_MS
                trace("sweep: %s is in %s and not worn - dropping it to the floor",
                        describe(cart), containerName(cart:getContainer()))
                ISInventoryPaneContextMenu.dropItem(cart, _player:getPlayerNum())
            end
        end
    end
end

-- One line whenever what matters about this player's cart changes.
local function traceChanges(_player, _cart, _attached, _load, _factor)
    if not COOPCart.debug then return end
    local index = _player:getPlayerNum()
    local state = {
        cart = _cart and _cart:getID() or nil,
        attached = _attached and _attached:getID() or nil,
        load = _load and math.floor(_load * 10 + 0.5) / 10 or nil,
        factor = _factor and math.floor(_factor * 100 + 0.5) / 100 or nil,
    }
    local last = lastState[index]
    if last ~= nil and last.cart == state.cart and last.attached == state.attached
            and last.load == state.load and last.factor == state.factor then
        return
    end
    lastState[index] = state

    if _cart == nil then
        trace("state %s: no cart worn%s", COOP.playerName(_player),
                _attached ~= nil and (", model still attached: " .. describe(_attached)) or "")
        return
    end

    local capacity, weight = "?", "?"
    pcall(function() capacity = tostring(_cart:getInventory():getEffectiveCapacity(_player)) end)
    pcall(function() weight = string.format("%.2f", _player:getInventory():getCapacityWeight()) end)
    trace("state %s: pulling %s, capacity %s, model %s, speed x%.2f (walk %.3f run %.3f sprint %.3f), inventory weight %s / %.1f",
            COOP.playerName(_player), describe(_cart), capacity,
            _attached == _cart and "attached" or ("NOT attached (" .. describe(_attached) .. ")"),
            _factor, COOPCart.WALK_SCALE * _factor, COOPCart.RUN_SCALE * _factor,
            COOPCart.SPRINT_SCALE * _factor, weight, _player:getMaxWeight())
end

-- The worn cart, made sure to be the inventory's own object.
--
-- When the server confirms a wear, SyncClothingPacket.process() on the client puts the
-- inventory item with that id into the worn slot - or, if it cannot find it in the
-- inventory at that instant, a brand-new item of the same type and id
-- (InventoryItemFactory.CreateItem + setID). That copy has an empty container of its
-- own, so everything read off it is wrong: the load is 0, the real cart counts as
-- unworn (full weight, no reduction), and parking it parks the copy. So whatever sits in
-- the slot is checked against the inventory and the real item is put back.
function COOPCartUI.wornCart(_player)
    local worn = COOPCart.getWornCart(_player)
    if worn == nil then return nil end

    local real = _player:getInventory():getItemWithID(worn:getID())
    if real == nil then
        traceOnce("noreal" .. tostring(worn:getID()), "worn %s is not in the inventory at all", describe(worn))
        return worn
    end
    if real ~= worn then
        local location = COOPCart.bodyLocation()
        trace("worn slot held a copy of the cart (%s) - putting the inventory's own item back (%s)",
                describe(worn), describe(real))
        if location ~= nil then _player:getWornItems():setItem(location, real) end
        pcall(function() getPlayerInventory(_player:getPlayerNum()):refreshBackpacks() end)
    end
    return real
end

function COOPCartUI.reconcile(_player)
    local enabled = COOPCart.isEnabled()
    local cart = enabled and COOPCartUI.wornCart(_player) or nil
    local attached = _player:getAttachedItem(COOPCart.LOCATION)
    local load, factor = nil, nil

    if cart ~= nil then
        local id = cart:getID()
        if pending[id] ~= nil then
            trace("attach finished: %s is worn", describe(cart))
            pending[id] = nil
        end

        -- still worn once the queue is empty means the park was cancelled
        if detaching[id] ~= nil and (detaching[id] <= now() or not _player:hasTimedActions()) then
            trace("detach of %s was cancelled or timed out - putting the model back", tostring(id))
            detaching[id] = nil
        end
        if detaching[id] == nil and attached ~= cart then
            trace("setAttachedItem('%s', %s) - was %s", COOPCart.LOCATION, describe(cart), describe(attached))
            _player:setAttachedItem(COOPCart.LOCATION, cart)
            attached = _player:getAttachedItem(COOPCart.LOCATION)
            if COOPCart.clearParent(cart) then
                trace("cleared the parent setAttachedItem gave %s's container", tostring(id))
            end
            if attached ~= cart then
                trace("setAttachedItem did not stick - getAttachedItem answers %s", describe(attached))
            end
        end

        if COOPCart.clearParent(cart) then
            trace("%s's container had a parent again - cleared", tostring(id))
        end

        load = COOPCart.loadWeight(cart)
        factor = COOPCart.speedFactor(load)
        setAnim(_player, true)
        setVaultBlocked(_player, true)
        _player:setVariable("COOPCartWalkSpeed", COOPCart.WALK_SCALE * factor)
        _player:setVariable("COOPCartRunSpeed", COOPCart.RUN_SCALE * factor)
        _player:setVariable("COOPCartSprintSpeed", COOPCart.SPRINT_SCALE * factor)
    else
        if attached ~= nil then
            trace("removing the pulled model %s - no cart worn", describe(attached))
            _player:setAttachedItem(COOPCart.LOCATION, nil)
            attached = nil
        end
        setAnim(_player, false)
        setVaultBlocked(_player, false)
    end

    traceChanges(_player, cart, attached, load, factor)
    sweepInventory(_player, enabled)
end

local function onPlayerUpdate(_player)
    if _player == nil or not _player:isLocalPlayer() then return end
    local index = _player:getPlayerNum()
    local t = now()
    if nextCheck[index] ~= nil and nextCheck[index] > t then return end
    nextCheck[index] = t + CHECK_MS

    local ok, err = pcall(COOPCartUI.reconcile, _player)
    if not ok then COOP.log("cart: reconcile failed: " .. tostring(err)) end
end

-- Everything about the local players' carts, whatever COOPCart.debug says. Call it from
-- the debug console.
function COOPCartUI.dump()
    local out = {}
    local function line(_fmt, ...) table.insert(out, string.format(_fmt, ...)) end

    line("enabled %s, debug %s, side %s", tostring(COOPCart.isEnabled()), tostring(COOPCart.debug),
            isClient() and "client" or "sp")
    for _, name in ipairs(COOPCartUI.BODY_MODELS) do
        local script = getScriptManager():getModelScript(name)
        local attachment = script and script:getAttachmentById(COOPCart.ATTACHMENT)
        line("  %s: %s", name, attachment and attachmentText(attachment) or "NO coop_cart attachment")
    end
    local modelOk, worldModel = pcall(function() return getScriptManager():getModelScript("COOPCartWorld") end)
    line("  model script COOPCartWorld: %s", (modelOk and worldModel ~= nil) and "found" or "MISSING")

    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player ~= nil then
            local cart = COOPCartUI.wornCart(player)
            line("player %d (%s) at %d,%d,%d, vehicle %s, timed actions %s", i, COOP.playerName(player),
                    math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ()),
                    tostring(player:getVehicle() ~= nil), tostring(player:hasTimedActions()))
            line("  back slot: %s, cart slot '%s': %s (location %s)", describe(backItem(player)),
                    COOPCart.BODY_LOCATION, describe(cartSlotItem(player)),
                    COOPCart.bodyLocation() ~= nil and "registered" or "NOT REGISTERED")
            line("  worn cart: %s", describe(cart))
            line("  attached at '%s': %s", COOPCart.LOCATION, describe(player:getAttachedItem(COOPCart.LOCATION)))
            if cart ~= nil then
                local load = COOPCart.loadWeight(cart)
                local factor = COOPCart.speedFactor(load)
                pcall(function()
                    line("  cart capacity %d (effective %d), items %d, load %.2f kg, equipped weight %.2f",
                            cart:getInventory():getCapacity(), cart:getInventory():getEffectiveCapacity(player),
                            cart:getInventory():getItems():size(), load, cart:getEquippedWeight())
                end)
                line("  speed factor %.3f", factor)
                pcall(function()
                    line("  cart container parent: %s (must be nil)", tostring(cart:getInventory():getParent()))
                end)
            end
            pcall(function()
                line("  anim vars: COOPCart=%s walk=%s run=%s sprint=%s | WalkSpeed=%s",
                        tostring(player:getVariableString("COOPCart")),
                        tostring(player:getVariableString("COOPCartWalkSpeed")),
                        tostring(player:getVariableString("COOPCartRunSpeed")),
                        tostring(player:getVariableString("COOPCartSprintSpeed")),
                        tostring(player:getVariableString("WalkSpeed")))
            end)
            pcall(function()
                line("  inventory weight %.2f / %.1f, ignoreAutoVault %s", player:getInventory():getCapacityWeight(),
                    player:getMaxWeight(), tostring(player:isIgnoreAutoVault()))
            end)
            local carts = player:getInventory():getAllTypeRecurse(COOPCart.ITEM)
            for j = 0, carts:size() - 1 do
                local c = carts:get(j)
                line("  cart in inventory: %s in %s, worn %s", describe(c), containerName(c:getContainer()),
                        tostring(player:isEquippedClothing(c)))
            end
        end
    end

    local t = now()
    for id, until_ in pairs(pending) do line("pending attach: %s, %d ms left", tostring(id), until_ - t) end
    for id, until_ in pairs(detaching) do line("detaching: %s, %d ms left", tostring(id), until_ - t) end
    for id, until_ in pairs(dropQueued) do line("drop queued: %s, %d ms left", tostring(id), until_ - t) end

    for _, text in ipairs(out) do print("[CO-OP] cart dump: " .. text) end
    return #out
end

-- ---------------------------------------------------------------------------
-- what a cart stops you doing
--
-- Every one of these goes through a vanilla timed action, so an isValid that says no
-- is enough: the action is dropped before it starts, the same as when the fence or the
-- car door is not there. Vaulting a fence at a run is one of them too - IsoPlayer sends
-- it through the ClimbOverFence contextual action, which ends in ISClimbOverFence.
-- ---------------------------------------------------------------------------

local function blockWhilePulling(_class, _className, _messageKey)
    if _class == nil then
        trace("hook: %s does not exist, not blocked", _className)
        return
    end
    if _class.isValid == nil or _class.COOPCartOriginalIsValid ~= nil then return end
    local original = _class.isValid
    _class.COOPCartOriginalIsValid = original
    _class.isValid = function(self, ...)
        if pulling(self.character) then
            traceOnce(_className, "blocked %s - pulling a cart", _className)
            say(self.character, _messageKey)
            return false
        end
        return original(self, ...)
    end
    trace("hook: %s:isValid blocks while pulling", _className)
end

-- Where a cart may be moved to: the floor always; the player's own main inventory only
-- on its way to their back.
local function cartMayGo(_character, _item, _dest)
    if _dest == nil then return true end
    if _dest:getType() == "floor" then return true end
    if _character ~= nil and _dest == _character:getInventory() and isPending(_item) then return true end
    return false
end

local function installHooks()
    blockWhilePulling(ISClimbOverFence, "ISClimbOverFence", "UI_COOP_Cart_NoClimb")
    blockWhilePulling(ISClimbThroughWindow, "ISClimbThroughWindow", "UI_COOP_Cart_NoClimb")
    blockWhilePulling(ISClimbSheetRopeAction, "ISClimbSheetRopeAction", "UI_COOP_Cart_NoClimb")
    blockWhilePulling(ISEnterVehicle, "ISEnterVehicle", "UI_COOP_Cart_NoVehicle")

    if ISInventoryTransferAction ~= nil and ISInventoryTransferAction.COOPCartOriginalIsValid == nil then
        local original = ISInventoryTransferAction.isValid
        ISInventoryTransferAction.COOPCartOriginalIsValid = original
        ISInventoryTransferAction.isValid = function(self, ...)
            if self.item ~= nil and COOPCart.isEnabled() and COOPCart.isCart(self.item) then
                if not cartMayGo(self.character, self.item, self.destContainer) then
                    traceOnce("transfer" .. tostring(self.item:getID()),
                            "blocked transfer of %s: %s -> %s (pending %s)", describe(self.item),
                            containerName(self.srcContainer), containerName(self.destContainer),
                            tostring(isPending(self.item)))
                    say(self.character, "UI_COOP_Cart_NoCarry")
                    return false
                end
                local result = original(self, ...)
                traceOnce("transferok" .. tostring(self.item:getID()),
                        "transfer of %s: %s -> %s allowed by the cart rules, vanilla isValid says %s",
                        describe(self.item), containerName(self.srcContainer),
                        containerName(self.destContainer), tostring(result))
                return result
            end
            return original(self, ...)
        end
        trace("hook: ISInventoryTransferAction:isValid keeps carts on the floor or the back")
    end

    -- the single-player "Grab" off the ground, which is not a transfer action
    if ISGrabItemAction ~= nil and ISGrabItemAction.COOPCartOriginalIsValid == nil then
        local original = ISGrabItemAction.isValid
        ISGrabItemAction.COOPCartOriginalIsValid = original
        ISGrabItemAction.isValid = function(self, ...)
            local item = nil
            pcall(function() item = self.item:getItem() end)
            if item ~= nil and COOPCart.isEnabled() and COOPCart.isCart(item) and not isPending(item) then
                traceOnce("grab" .. tostring(item:getID()), "blocked grabbing %s off the ground", describe(item))
                say(self.character, "UI_COOP_Cart_NoCarry")
                return false
            end
            return original(self, ...)
        end
        trace("hook: ISGrabItemAction:isValid blocks grabbing a cart")
    end

    if ISEquipWeaponAction ~= nil and ISEquipWeaponAction.COOPCartOriginalIsValid == nil then
        local original = ISEquipWeaponAction.isValid
        ISEquipWeaponAction.COOPCartOriginalIsValid = original
        ISEquipWeaponAction.isValid = function(self, ...)
            if self.item ~= nil and COOPCart.isEnabled() and COOPCart.isCart(self.item) then
                traceOnce("equip" .. tostring(self.item:getID()), "blocked equipping %s in the hands", describe(self.item))
                say(self.character, "UI_COOP_Cart_NoCarry")
                return false
            end
            return original(self, ...)
        end
        trace("hook: ISEquipWeaponAction:isValid keeps carts out of the hands")
    end

    -- Vanilla "Wear" on a cart lying in the loot window is attaching it.
    if ISInventoryPaneContextMenu ~= nil and ISInventoryPaneContextMenu.COOPCartOriginalWear == nil then
        local original = ISInventoryPaneContextMenu.wearItem
        ISInventoryPaneContextMenu.COOPCartOriginalWear = original
        ISInventoryPaneContextMenu.wearItem = function(item, player, ...)
            if COOPCart.isEnabled() and COOPCart.isCart(item) then
                local playerObj = getSpecificPlayer(player)
                trace("vanilla Wear on %s redirected to attach", describe(item))
                if playerObj ~= nil then
                    local problem = COOPCartUI.attachProblem(playerObj, item)
                    if problem ~= nil then
                        trace("attach refused: %s", problem)
                        say(playerObj, problem)
                    else
                        COOPCartUI.attach(playerObj, item)
                    end
                end
                return
            end
            return original(item, player, ...)
        end
        trace("hook: ISInventoryPaneContextMenu.wearItem turns Wear on a cart into attach")
    end
end

-- ---------------------------------------------------------------------------
-- menus
-- ---------------------------------------------------------------------------

local function disable(_option, _text)
    _option.notAvailable = true
    local tooltip = ISToolTip:new()
    tooltip:initialise()
    tooltip:setVisible(false)
    tooltip.description = _text
    _option.toolTip = tooltip
end

local function addAttachOption(_context, _player, _item, _where)
    local option = _context:addOption(getText("ContextMenu_COOP_Cart_Attach"), _player, COOPCartUI.attach, _item)
    pcall(function() option.iconTexture = _item:getTex() end)

    local problem = COOPCartUI.attachProblem(_player, _item)
    traceOnce("menuattach" .. _where, "%s menu: Attach cart for %s%s", _where, describe(_item),
            problem and (" - disabled: " .. problem) or "")
    if problem ~= nil then
        disable(option, getText(problem))
    end
end

local function addDetachOption(_context, _player, _cart, _where)
    traceOnce("menudetach" .. _where, "%s menu: Detach cart for %s", _where, describe(_cart))
    local option = _context:addOption(getText("ContextMenu_COOP_Cart_Detach"), _player, COOPCartUI.detach, _cart)
    pcall(function() option.iconTexture = _cart:getTex() end)
end

-- Right-click in the world: attach a parked cart on the clicked squares, or park the
-- one you are pulling wherever you clicked.
local function onFillWorldObjectContextMenu(_playerNum, _context, _worldobjects, _test)
    if _test and ISWorldObjectContextMenu.Test then return true end
    if not COOPCart.isEnabled() then return end

    local player = getSpecificPlayer(_playerNum)
    if player == nil or player:getVehicle() ~= nil then return end

    local worn = COOPCartUI.wornCart(player)
    if worn ~= nil then
        if _test then return ISWorldObjectContextMenu.setTest() end
        addDetachOption(_context, player, worn, "world")
        return
    end

    local found = nil
    local seen = {}
    for _, object in ipairs(_worldobjects) do
        local square = object:getSquare()
        if square ~= nil and not seen[square] then
            seen[square] = true
            local items = square:getWorldObjects()
            for i = 0, items:size() - 1 do
                local item = items:get(i):getItem()
                if COOPCart.isCart(item) then found = item; break end
            end
        end
        if found ~= nil then break end
    end
    if found == nil then return end

    if _test then return ISWorldObjectContextMenu.setTest() end
    addAttachOption(_context, player, found, "world")
end

-- Right-click in the inventory or the loot window.
local function onFillInventoryObjectContextMenu(_playerNum, _context, _items)
    if not COOPCart.isEnabled() then return end
    local player = getSpecificPlayer(_playerNum)
    if player == nil then return end

    local items = ISInventoryPane.getActualItems(_items)
    for _, item in ipairs(items) do
        if COOPCart.isCart(item) then
            if player:isEquippedClothing(item) then
                addDetachOption(_context, player, item, "inventory")
            elseif item:getWorldItem() ~= nil then
                addAttachOption(_context, player, item, "inventory")
            else
                traceOnce("menunone", "inventory menu: %s is in %s - neither worn nor parked, no option",
                        describe(item), containerName(item:getContainer()))
            end
            return
        end
    end
end

-- ---------------------------------------------------------------------------
-- wiring
-- ---------------------------------------------------------------------------

local function onGameStart()
    trace("game start: enabled %s", tostring(COOPCart.isEnabled()))
    COOPCartUI.ensureBodyAttachments("OnGameStart")
    installHooks()
end

COOPCartUI.ensureBodyAttachments("file load")

Events.OnGameBoot.Add(function() COOPCartUI.ensureBodyAttachments("OnGameBoot") end)
Events.OnGameStart.Add(onGameStart)
Events.OnCreatePlayer.Add(function() COOPCartUI.ensureBodyAttachments("OnCreatePlayer") end)
Events.OnPlayerUpdate.Add(onPlayerUpdate)
Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)
