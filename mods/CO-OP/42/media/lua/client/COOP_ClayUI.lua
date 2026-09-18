--
-- CO-OP - the clay dig: the menu entry, the action, and the client's view of the
-- per-square cooldown.
--
-- The action is the visible half of the feature and does none of the work: it plays
-- vanilla's garden-plot dig and then tells the server where it dug. The clay, the XP and
-- the cooldown are all the server's, for the reasons in COOP_ClayServer.lua.
--
-- The cooldown cache is here for one purpose only - greying out the menu entry on a bank
-- somebody has already worked this week, so a player is not made to watch a full dig
-- before being told no. It is never trusted for anything: the server checks the cooldown
-- again whatever the client believed.
--

if isServer() then return end

require "COOP_Clay"
require "TimedActions/ISBaseTimedAction"

COOPClayUI = COOPClayUI or {}

local cache = {}
local synced = false
local nextRequestMs = 0

local REQUEST_RETRY_MS = 10000

-- ---------------------------------------------------------------------------
-- the cooldown, as this client sees it
-- ---------------------------------------------------------------------------

function COOPClayUI.getEntries()
    if isClient() then return cache end
    if COOPClayServer ~= nil then return COOPClayServer.getEntries() end
    return {}
end

-- Days before this square gives clay again, 0 when it is ready.
function COOPClayUI.cooldownLeft(_square)
    if _square == nil then return 0 end
    local key = COOPClay.squareKey(_square:getX(), _square:getY(), _square:getZ())
    return COOPClay.cooldownLeft(COOPClayUI.getEntries(), key)
end

-- The server drops an entry the moment its cooldown runs out, but it does not spend a
-- broadcast saying so - an expired entry and a missing one answer the same thing to
-- cooldownLeft. That leaves the cache to tidy itself, which it does every time a new dig
-- arrives, so a long session cannot accumulate a week of dead keys.
local function pruneCache()
    local stale = {}
    for key, _ in pairs(cache) do
        if COOPClay.cooldownLeft(cache, key) <= 0 then table.insert(stale, key) end
    end
    for _, key in ipairs(stale) do cache[key] = nil end
end

local function onServerCommand(_module, _command, _args)
    if _module ~= COOPClay.MODULE then return end

    if _command == COOPClay.CMD_SYNC then
        cache = (_args and _args.entries) or {}
        synced = true
    elseif _command == COOPClay.CMD_DELTA then
        if _args == nil or _args.key == nil then return end
        if _args.removed or _args.day == nil then
            cache[_args.key] = nil
        else
            cache[_args.key] = _args.day
        end
        pruneCache()
    elseif _command == COOPClay.CMD_RESULT then
        COOPClayUI.report(_args and _args.amount or 0, _args and _args.reason or nil)
    end
end

local function requestSync()
    if not isClient() then return end
    nextRequestMs = getTimestampMs() + REQUEST_RETRY_MS
    sendClientCommand(getPlayer(), COOPClay.MODULE, COOPClay.CMD_SYNC_REQUEST, {})
end

-- Keep asking until the server answers: the first request can land before the player is
-- fully connected.
local function onTick()
    if not isClient() or synced then return end
    if not COOPClay.isEnabled() then return end
    if getPlayer() == nil then return end
    if getTimestampMs() < nextRequestMs then return end
    requestSync()
end

Events.OnServerCommand.Add(onServerCommand)
Events.OnTick.Add(onTick)
Events.OnCreatePlayer.Add(function()
    synced = false
    nextRequestMs = 0
end)

-- What came of a dig, in the digger's own chat window. The clay can land in a crate
-- across the room if the output picker says so, so "you got three" is worth saying out
-- loud rather than leaving the player to go and count.
function COOPClayUI.report(_amount, _reason)
    local amount = tonumber(_amount) or 0

    if amount > 0 then
        COOP.sayInChat(getText("UI_COOP_Clay_Dug", tostring(amount)))
        return
    end

    if _reason == "cooldown" then
        COOP.sayInChat(getText("UI_COOP_Clay_Refused"))
    elseif _reason == "where" or _reason == "full" then
        COOP.sayInChat(getText("UI_COOP_Clay_Nothing"))
    end
end

-- ---------------------------------------------------------------------------
-- the action
--
-- Mirrors ISPlowAction, which is the garden-plot dig: the same metabolic target, the
-- same sound, the same animation picked by BuildingHelper.getShovelAnim, the same job
-- bar on the shovel's icon. Vanilla does not wear a shovel down for digging - neither
-- ISPlowAction nor ISShovelGround touches its condition - so neither do we.
--
-- It deliberately has **no `complete`**. A timed action whose class defines one is
-- shipped to the server and rebuilt there by reflecting over the parameter names of its
-- `new`, and would then run its `complete` on both sides - which for us would mean two
-- lots of clay for one hole. The work is in `perform` and the request goes over the
-- command channel, exactly as the push action does.
-- ---------------------------------------------------------------------------

COOPClayAction = ISBaseTimedAction:derive("COOPClayAction")

function COOPClayAction:isValid()
    if not COOPClay.isEnabled() then return false end
    if self.square == nil or not COOPClay.canDigSquare(self.square) then return false end
    if self.item == nil then return false end
    return self.character:getInventory():containsID(self.item:getID())
end

function COOPClayAction:waitToStart()
    self.character:faceLocation(self.square:getX(), self.square:getY())
    return self.character:isTurning() or self.character:shouldBeTurning()
end

function COOPClayAction:update()
    self.character:faceLocation(self.square:getX(), self.square:getY())
    if self.item then
        self.item:setJobDelta(self:getJobDelta())
    end
    -- vanilla's own exertion figure for digging with a spade; this is the stamina cost
    self.character:setMetabolicTarget(Metabolics.DiggingSpade)
end

function COOPClayAction:start()
    -- the item can be a different Lua object by the time the action runs
    if isClient() and self.item then
        self.item = self.character:getInventory():getItemById(self.item:getID())
    end

    if self.item then
        self.item:setJobType(getText("ContextMenu_COOP_Clay"))
        self.item:setJobDelta(0.0)
        self:setOverrideHandModels(self.item:getStaticModel(), nil)
    end

    self.sound = self.character:playSound("DigFurrowWithShovel")
    -- the noise the digging makes in the world, same radius as a furrow
    addSound(self.character, self.character:getX(), self.character:getY(), self.character:getZ(), 10, 1)

    -- BuildingHelper picks the clip from the tool - a spade swings, an entrenching tool
    -- scrapes. It is read at this moment rather than required at the top of the file:
    -- requiring a vanilla file makes the game load it early and then again on its own
    -- scan, which is what silently broke the craft hook once already.
    local anim = CharacterActionAnims ~= nil and CharacterActionAnims.DigShovel or "DigShovel"
    if BuildingHelper ~= nil and BuildingHelper.getShovelAnim ~= nil then
        anim = BuildingHelper.getShovelAnim(self.item) or anim
    end
    self:setActionAnim(anim)
end

function COOPClayAction:stop()
    if self.sound and self.sound ~= 0 then
        self.character:getEmitter():stopOrTriggerSound(self.sound)
    end
    ISBaseTimedAction.stop(self)
    if self.item then
        self.item:setJobDelta(0.0)
    end
end

function COOPClayAction:perform()
    if self.sound and self.sound ~= 0 then
        self.character:getEmitter():stopOrTriggerSound(self.sound)
    end
    if self.item then
        self.item:getContainer():setDrawDirty(true)
        self.item:setJobDelta(0.0)
    end

    -- The strain ISPlowAction applies in its own complete(). Ours has no complete, so it
    -- happens here, on the digger's own client - which is where the local player's body
    -- is simulated anyway. Scaled by the same perk the yield uses rather than Farming.
    pcall(function()
        local strain = (1 - (COOPClay.perkLevel(self.character) * 0.05)) * 0.5
        self.character:addArmMuscleStrain(strain)
        self.character:addBackMuscleStrain(strain)
    end)

    if self.square ~= nil then
        local args = {
            x = self.square:getX(),
            y = self.square:getY(),
            z = self.square:getZ(),
        }
        if isClient() then
            sendClientCommand(self.character, COOPClay.MODULE, COOPClay.CMD_DIG, args)
        elseif COOPClayServer ~= nil then
            -- Single player: one Lua state, so call the authority and answer at once.
            -- The action goes with it because it is carrying the output destinations.
            local amount, reason = COOPClayServer.dig(self.character, args, self)
            COOPClayUI.report(amount, reason)
        end
    end

    ISBaseTimedAction.perform(self)
end

function COOPClayAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return COOPClay.DIG_TIME
end

function COOPClayAction:new(character, square, item)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.square = square
    o.item = item
    o.maxTime = o:getDuration()
    o.caloriesModifier = 5
    return o
end

-- ---------------------------------------------------------------------------
-- the world context menu
-- ---------------------------------------------------------------------------

-- IsoMovingObject.DistToProper takes an IsoObject, not an IsoGridSquare, so the distance
-- to a bare square is measured here rather than asked for - the same Chebyshev test the
-- server makes of the same claim.
local function withinReach(_player, _square, _reach)
    local dx = math.abs(_player:getX() - (_square:getX() + 0.5))
    local dy = math.abs(_player:getY() - (_square:getY() + 0.5))
    return math.max(dx, dy) <= _reach
end

local function disable(_option, _reason)
    if _option == nil then return end
    _option.notAvailable = true
    if _reason ~= nil and ISWorldObjectContextMenu and ISWorldObjectContextMenu.addToolTip then
        local tooltip = ISWorldObjectContextMenu.addToolTip()
        tooltip.description = _reason
        _option.toolTip = tooltip
    end
end

local function onDig(_player, _square, _shovel)
    if not luautils.walkAdj(_player, _square, true) then return end

    -- Put the shovel in hand the way the farming cursor does, so the dig animation has
    -- the tool it is holding.
    pcall(function()
        ISInventoryPaneContextMenu.equipWeapon(_shovel, true, _shovel:isTwoHandWeapon(), _player:getPlayerNum())
    end)

    local action = COOPClayAction:new(_player, _square, _shovel)

    -- Where the clay lands follows the mod's own output picker, under the smithing
    -- category - the skill this dig trains. Stamping also pushes the whole set to the
    -- server, which is what keeps a "nearby container" destination pointing at the
    -- container the player is standing next to now and not the one they crafted at.
    if COOPOutput ~= nil and COOPOutput.stampAction ~= nil then
        pcall(function() COOPOutput.stampAction(action) end)
    end

    ISTimedActionQueue.add(action)
end

local function onFillWorldObjectContextMenu(_playerNum, _context, _worldobjects, _test)
    if _test and ISWorldObjectContextMenu.Test then return true end
    if not COOPClay.isEnabled() then return end

    local player = getSpecificPlayer(_playerNum)
    if player == nil or player:getVehicle() ~= nil then return end

    -- The clicked squares rather than the objects, and de-duplicated: a riverbank square
    -- carries a floor, grass overlays and often a bush, and the picker answers with
    -- whichever of them was on top. Same reasoning as ISFarmingMenu.canDigHere.
    local square = nil
    local seen = {}
    for _, object in ipairs(_worldobjects) do
        local candidate = object:getSquare()
        if candidate ~= nil and not seen[candidate] then
            seen[candidate] = true
            if withinReach(player, candidate, COOPClay.REACH)
                    and COOPClay.canDigSquare(candidate) then
                square = candidate
                break
            end
        end
    end
    if square == nil then return end

    if _test then return ISWorldObjectContextMenu.setTest() end

    local shovel = COOPClay.findShovel(player)

    local option = _context:addOption(getText("ContextMenu_COOP_Clay"), player, onDig, square, shovel)
    pcall(function() option.iconTexture = getTexture("Item_Clay") end)

    if shovel == nil then
        disable(option, getText("ContextMenu_COOP_Clay_NoShovel"))
        return
    end

    local left = COOPClayUI.cooldownLeft(square)
    if left > 0 then
        disable(option, COOPClay.waitText(left))
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
