--
-- CO-OP - the Push option and the action behind it.
--
-- The slice goes into the vehicle radial menu (V) when the player is standing at the
-- front or the back of a vehicle; the action holds them there, leaning on it, until
-- Esc or anything else interrupts them.
--
-- See shared/COOP_Push.lua for the model, the coordinate conventions and why there is
-- no server half to this feature.
--

if isServer() then return end

require "TimedActions/ISBaseTimedAction"
require "COOP_Push"

COOPPushUI = COOPPushUI or {}

local ICON = "media/ui/COOP_Push.png"

-- If a tick ever asks the character to move further than this in one go, something has
-- happened to the vehicle that is not pushing - it was teleported, or the chunk it is
-- in reloaded - and dragging the character along would be worse than letting go.
local MAX_STEP = 0.75

-- --------------------------------------------------------------------------
-- the action
-- --------------------------------------------------------------------------

COOPPushAction = ISBaseTimedAction:derive("COOPPushAction")

-- There is deliberately no `complete` on this class. ISBaseTimedAction only sets
-- useCustomRemoteTimedActionSync when the class has none, and it is that flag which
-- keeps the action off the multiplayer timed-action path - where the server would
-- rebuild it by reflecting over the parameter names of `new` and run a second copy
-- that could not move anything anyway.
function COOPPushAction:isValid()
    if self.vehicle == nil then return false end
    -- read every tick, not once: switching the feature off on a running server should
    -- put down whatever is being pushed rather than wait for the next relog
    if not COOPPush.isEnabled() then return false end

    local ok, valid = pcall(function()
        if self.vehicle:isRemovedFromWorld() then return false end
        if self.character:getVehicle() ~= nil then return false end
        -- still the same end of the same vehicle, still within arm's reach
        return COOPPush.endFor(self.vehicle, self.character) == self.side
    end)

    return ok and valid == true
end

function COOPPushAction:waitToStart()
    self.character:faceLocationF(self.vehicle:getX(), self.vehicle:getY())
    return self.character:shouldBeTurning()
end

function COOPPushAction:start()
    self:setActionAnim(COOPPush.ANIM)
    -- bare hands on the bodywork: whatever was being carried should not be in shot
    self:setOverrideHandModels(nil, nil)

    COOPPush.claim(self.vehicle, self.character)

    -- Where the player is standing, in the vehicle's own frame. Every tick puts them
    -- back at this spot, so they travel and turn with the vehicle instead of watching
    -- it roll out from under their hands.
    pcall(function()
        local here = Vector3f.new()
        self.vehicle:getLocalPos(self.character:getX(), self.character:getY(),
                self.character:getZ(), here)
        self.grip = { x = here:x(), y = here:y(), z = here:z() }
    end)

    self.claimAt = getTimestampMs()
end

-- Moves the character back to the spot on the vehicle they took hold of. Returns false
-- when that spot is somewhere they cannot be, which ends the push.
function COOPPushAction:follow()
    if self.grip == nil then return true end

    local ok, moved = pcall(function()
        local there = Vector3f.new()
        self.vehicle:getWorldPos(self.grip.x, self.grip.y, self.grip.z, there)

        local x, y = there:x(), there:y()
        local dx, dy = x - self.character:getX(), y - self.character:getY()
        if dx * dx + dy * dy > MAX_STEP * MAX_STEP then return false end

        -- the character keeps their own floor; the vehicle's local y is a height above
        -- its chassis and means nothing to somebody standing on the ground
        local z = self.character:getZ()
        if getCell():getGridSquare(x, y, z) == nil then return false end

        self.character:setX(x)
        self.character:setY(y)
        -- the "last" position is what the renderer interpolates from; leaving it behind
        -- smears the character across the gap every frame
        self.character:setLastX(x)
        self.character:setLastY(y)
        self.character:setCurrentSquareFromPosition()
        return true
    end)

    return ok and moved == true
end

function COOPPushAction:update()
    -- Esc, or whatever CancelAction is bound to - shared/keyBinding.lua binds
    -- "CancelAction" to KEY_ESCAPE and it is rebindable there. Vanilla's own walk-to
    -- and path-find actions ask the same question. Walking off, running or aiming is
    -- already covered by stopOnWalk / stopOnRun / stopOnAim, which the base class turns
    -- on by default and this action leaves on.
    if self.character:pressedCancelAction() then
        self:forceStop()
        return
    end

    local endurance = 1
    pcall(function() endurance = self.character:getStats():get(CharacterStat.ENDURANCE) end)
    if endurance <= 0.02 then
        HaloTextHelper.addBadText(self.character, getText("UI_COOP_Push_Exhausted"))
        self:forceStop()
        return
    end

    -- Leaning on a car is the heaviest thing the metabolism has a name for. The engine
    -- turns this into the endurance drain and the sweat; nothing else touches the stat.
    self.character:setMetabolicTarget(Metabolics.HeavyWork)
    self.character:faceLocationF(self.vehicle:getX(), self.vehicle:getY())

    -- It is going faster than any push of ours could explain: let go rather than be
    -- towed along by our own follow() below.
    if COOPPush.isRunaway(self.vehicle) then
        self:forceStop()
        return
    end

    local fx, fy = COOPPush.forwardOf(self.vehicle)
    if fx == nil then
        self:forceStop()
        return
    end

    COOPPush.push(self.vehicle, COOPPush.signFor(self.side), fx, fy)

    if not self:follow() then
        self:forceStop()
        return
    end

    -- Authorization is a lease, not a deed: a client that stops touching a vehicle
    -- loses it again, and losing it half way through a push leaves the car juddering
    -- between what we are doing to it and what its owner says. Renewing it once a
    -- second is cheap and matches how often vanilla re-collides.
    local now = getTimestampMs()
    if now - (self.claimAt or 0) > 1000 then
        self.claimAt = now
        COOPPush.claim(self.vehicle, self.character)
    end
end

function COOPPushAction:new(character, vehicle, side)
    local o = ISBaseTimedAction.new(self, character)
    o.vehicle = vehicle
    o.side = side
    -- never finishes on its own: a negative maxTime also skips adjustMaxTime's moodle
    -- and pain multipliers entirely, which is what we want for something the player
    -- holds rather than performs
    o.maxTime = -1
    o.caloriesModifier = 4
    return o
end

-- --------------------------------------------------------------------------
-- the radial menu
-- --------------------------------------------------------------------------

-- Asked of the action queue rather than kept in a table of our own: the queue is the
-- thing that actually knows, and it cannot fall out of step with itself when an action
-- is dropped without ever having started.
function COOPPushUI.isPushing(_playerObj)
    if _playerObj == nil then return false end
    return ISTimedActionQueue.hasActionType(_playerObj, "COOPPushAction")
end

function COOPPushUI.onPush(_playerObj, _vehicle)
    if not COOPPush.isEnabled() then return end

    local ok, reason = COOPPush.canPush(_vehicle, _playerObj)
    if not ok then
        if reason ~= nil then HaloTextHelper.addBadText(_playerObj, getText(reason)) end
        return
    end

    -- Worked out again here rather than carried on the slice: the radial menu was built
    -- when the player pressed V and they can have walked round the car since.
    local side = COOPPush.endFor(_vehicle, _playerObj)
    if side == nil then
        HaloTextHelper.addBadText(_playerObj, getText("UI_COOP_Push_NotAtEnd"))
        return
    end

    ISTimedActionQueue.add(COOPPushAction:new(_playerObj, _vehicle, side))
end

function COOPPushUI.onStop(_playerObj)
    ISTimedActionQueue.clear(_playerObj)
end

local function fillPushSlice(_playerObj, _vehicle, _menu)
    if not COOPPush.isEnabled() then return end
    if _playerObj == nil or _vehicle == nil or _menu == nil then return end

    if COOPPushUI.isPushing(_playerObj) then
        _menu:addSlice(getText("ContextMenu_COOP_PushStop"), getTexture(ICON),
                COOPPushUI.onStop, _playerObj)
        return
    end

    -- Only say anything at all when the player is standing where a push would happen.
    -- Beside the car the option is meaningless and the radial menu is crowded enough.
    local side = COOPPush.endFor(_vehicle, _playerObj)
    if side == nil then return end

    local ok, reason = COOPPush.canPush(_vehicle, _playerObj)
    if not ok then
        -- a slice with no command is vanilla's way of showing why something is off -
        -- ISVehicleMenu does it for "stop the car first" and "not tired enough"
        if reason ~= nil then
            _menu:addSlice(getText(reason), getTexture(ICON), nil, _playerObj)
        end
        return
    end

    _menu:addSlice(getText("ContextMenu_COOP_Push"), getTexture(ICON),
            COOPPushUI.onPush, _playerObj, _vehicle)
end

-- --------------------------------------------------------------------------
-- hook
-- --------------------------------------------------------------------------

-- Our own installed function, so we can tell whether it is still in place: the game
-- re-runs its own class files after a mod requires them, which replaces the table and
-- drops anything a mod attached to it. See COOP_Output.lua for the full story - the
-- same trap, and the reason this file requires no vanilla vehicle file.
local installed = nil

-- ISVehicleMenu.doTowingMenu is the injection point rather than showRadialMenuOutside.
-- It is a plain function on a plain table, it is called from exactly one place -
-- ISVehicleMenu.lua:354, inside showRadialMenuOutside - and it is called for every
-- vehicle, before the `if menu:isEmpty() then return end` and the addToUIManager that
-- close that function out. Wrapping showRadialMenuOutside instead would mean either
-- adding slices after the menu is already on screen or re-implementing its tail.
--
-- Our slice goes in *before* the original runs, because doTowingMenu returns early for
-- a vehicle that is already towing or being towed.
local function install()
    if ISVehicleMenu == nil then return end
    if installed ~= nil and ISVehicleMenu.doTowingMenu == installed then return end

    local original = ISVehicleMenu.doTowingMenu
    if original == nil then return end

    local wrapper = function(playerObj, vehicle, menu)
        pcall(fillPushSlice, playerObj, vehicle, menu)
        return original(playerObj, vehicle, menu)
    end

    ISVehicleMenu.doTowingMenu = wrapper
    installed = wrapper
    COOP.log("push option installed")
end

Events.OnGameBoot.Add(install)
Events.OnGameStart.Add(install)
Events.OnInitGlobalModData.Add(install)
