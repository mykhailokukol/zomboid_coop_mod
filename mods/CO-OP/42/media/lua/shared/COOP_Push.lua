--
-- CO-OP - pushing a vehicle by hand.
--
-- Stand at the front or the back of a car or a trailer, open the vehicle radial menu
-- (V) and there is a Push option. The vehicle rolls at a walking pace that depends on
-- how heavy it is, the character stays glued to the bumper, and Esc (the vanilla
-- CancelAction binding) lets go.
--
-- This file holds the model: which end of a vehicle the player is standing at, how
-- fast that vehicle may be pushed, and the one call that actually moves it. The window
-- dressing - the radial slice and the timed action - is in client/COOP_PushUI.lua.
--
-- ---------------------------------------------------------------------------
-- Where this runs, and why there is no server half
-- ---------------------------------------------------------------------------
--
-- Every other shared thing in this mod is server authoritative. A vehicle's position
-- cannot be, because Build 42 does not simulate vehicle physics on the server at all.
-- Every Bullet entry point on BaseVehicle is behind the same guard - read out of the
-- bytecode of projectzomboid.jar, because none of this is visible from Lua:
--
--   BaseVehicle.update()            ... if (!GameServer.server) { apply impulseFromServer }
--   BaseVehicle.setWorldTransform() ... if (!GameServer.server) { Bullet.teleportVehicle }
--   applyAccumulatedImpulsesFromHitObjectsToPhysics()
--                                   ... applies only when this is a client holding
--                                       authorization for the vehicle, or neither
--                                       client nor server (i.e. single player)
--
-- So a handler on the server could take the request and would then have no way to act
-- on it: its impulses are dropped on the floor. The push therefore runs on the pushing
-- player's own client, which is the machine the engine already trusts to simulate that
-- vehicle, and the result reaches everyone else down the same wire that carries a car
-- somebody is driving. It is the same deal vanilla makes when you walk into a parked
-- car and it rocks: BaseVehicle.authorizationClientCollide() hands the colliding
-- player's client the simulation, and we call it for the same reason.
--
-- ---------------------------------------------------------------------------
-- Vehicle coordinates
-- ---------------------------------------------------------------------------
--
-- Three conventions are in play and they are not the same one:
--
--   * world       (x, y, z) with z the floor level - what getX/getY/getZ answer.
--   * vehicle     (x, y, z) = (lateral, vertical, along the vehicle), +z towards the
--                 front. This is what the vehicle scripts use: the front wheels of
--                 vehicle_car_normal_template sit at offset z = +0.72, the "Engine"
--                 area at +1.54 and "TruckBed" at -1.54.
--   * physics     (x, y, z) = (world x, height, world y). Bullet's axes.
--
-- getLocalPos(worldX, worldY, worldZ, out) goes world -> vehicle and
-- getWorldPos(localX, localY, localZ, out) goes back, so those two are all the mod
-- needs and neither of them touches the physics convention. addImpulse, on the other
-- hand, takes physics vectors - hence the (x, 0, y) shuffle in push() below.
--
-- getForwardVector() also answers in physics coordinates (it is literally a column of
-- the Bullet basis matrix), which is why the forward direction here is derived from
-- two getWorldPos calls instead: same answer, one convention fewer to get wrong.
--

require "COOP_Common"

COOPPush = COOPPush or {}

-- Turn this on to trace what the controller is doing - the vehicle's mass, the target
-- and current speed, and the force applied each tick. It is the first thing to look at
-- if a car will not budge or shoots off.
COOPPush.debug = false

-- ---------------------------------------------------------------------------
-- how fast, and how hard
-- ---------------------------------------------------------------------------

-- Weight classes, in the same kilos BaseVehicle:getMass() answers. Vanilla scripts run
-- from 200 (trailers) through 800-1000 (ordinary cars) to 1160 (vans and trucks), so
-- the two thresholds fall in the gaps rather than through the middle of a class.
COOPPush.MASS_LIGHT = 700
COOPPush.MASS_HEAVY = 1000

-- Defaults for the three speeds, in km/h. The sandbox options override them, so these
-- can be tuned in a running game without touching the mod.
--
-- The first draft was 5/3/1, which is walking pace down to slower than a shuffle and
-- made shifting a van across a car park a chore nobody would choose twice. These are
-- what one person can really do to a car on flat ground - a trailer can be got up to a
-- run, an ordinary car to a jog, a van to a brisk walk - and they stay under a sprint,
-- which is as fast as the character can plausibly travel while leaning on the bodywork.
COOPPush.SPEED_LIGHT = 10.0
COOPPush.SPEED_MEDIUM = 7.0
COOPPush.SPEED_HEAVY = 4.0

-- The hardest the push may shove, as an acceleration in m/s^2. Force is handed to
-- Bullet in newtons against a mass in kilos, so force/mass IS the acceleration - which
-- makes this number the one honest knob in the whole controller and keeps it safe
-- whatever the vehicle weighs: the worst a wrong value can do is reach the target
-- speed sooner, because push() stops pushing the moment the vehicle is at speed.
--
-- A person leaning on a car manages a fraction of this; the extra is what it takes to
-- get past the wheel friction Bullet applies, which is tuned for driving.
COOPPush.MAX_ACCEL = 2.0

-- Stop pushing once the vehicle is over its target, and let go entirely once it is
-- well over - at that point it is rolling away from you rather than being pushed.
COOPPush.RUNAWAY = 3.0

-- How far the player may stand from the vehicle's body and still reach it, in tiles.
COOPPush.REACH = 1.6

-- The fore/aft cone. The player counts as being at an end when they are further along
-- the vehicle than they are off to the side of it - which is what "at the front or the
-- back" means for a shape as long as a car, and it works for a trailer too, where the
-- Engine and TruckBed areas vanilla would use are missing.
COOPPush.CONE = 1.0

-- The character variable setActionAnim writes. media/AnimSets/player/actions/ is
-- searched across the game and every active mod (AnimationSet.Load goes through
-- ZomboidFileSystem.walkGameAndModFiles), so the mod ships its own node there and the
-- engine picks it up. Swap this for "VehicleTrailer" to fall back on a vanilla pose.
COOPPush.ANIM = "COOPPushVehicle"

function COOPPush.isEnabled()
    return COOP.featureEnabled(COOP.F_PUSH)
end

COOPPush.FRONT = "front"
COOPPush.REAR = "rear"

-- ---------------------------------------------------------------------------
-- the vehicle
-- ---------------------------------------------------------------------------

-- Kilos. getMass() is the live figure - parts and cargo included, because
-- updateTotalMass() keeps it that way - so a loaded truck is genuinely harder work
-- than an empty one. The script mass is the fallback for a vehicle whose physics body
-- has not been built yet.
function COOPPush.massOf(_vehicle)
    if _vehicle == nil then return 0 end

    local ok, mass = pcall(function() return _vehicle:getMass() end)
    if ok and mass ~= nil and mass > 0 then return mass end

    local okScript, scriptMass = pcall(function() return _vehicle:getScript():getMass() end)
    if okScript and scriptMass ~= nil and scriptMass > 0 then return scriptMass end

    return COOPPush.MASS_HEAVY
end

-- Target speed in km/h for this vehicle.
function COOPPush.speedFor(_vehicle)
    local mass = COOPPush.massOf(_vehicle)

    if mass <= COOPPush.MASS_LIGHT then
        return COOP.numberOption("PushSpeedLight", COOPPush.SPEED_LIGHT, 0.5, 20)
    end
    if mass <= COOPPush.MASS_HEAVY then
        return COOP.numberOption("PushSpeedMedium", COOPPush.SPEED_MEDIUM, 0.5, 20)
    end
    return COOP.numberOption("PushSpeedHeavy", COOPPush.SPEED_HEAVY, 0.5, 20)
end

-- The vehicle's forward direction as a unit vector in the world plane, or nil.
--
-- Taken as the difference between two points on the vehicle's own long axis rather
-- than from getForwardVector(), which answers in Bullet's axes - see the note at the
-- top of the file.
function COOPPush.forwardOf(_vehicle)
    if _vehicle == nil then return nil end

    local ok, fx, fy = pcall(function()
        local centre = Vector3f.new()
        local ahead = Vector3f.new()
        _vehicle:getWorldPos(0, 0, 0, centre)
        _vehicle:getWorldPos(0, 0, 1, ahead)
        return ahead:x() - centre:x(), ahead:y() - centre:y()
    end)
    if not ok or fx == nil then return nil end

    local length = math.sqrt(fx * fx + fy * fy)
    if length < 0.001 then return nil end

    return fx / length, fy / length
end

-- Which end of the vehicle the player is standing at: COOPPush.FRONT, COOPPush.REAR,
-- or nil when they are beside it, inside it or too far away. Also returns how far they
-- are from the vehicle's body, for the caller's error message.
function COOPPush.endFor(_vehicle, _player)
    if _vehicle == nil or _player == nil then return nil, nil end

    local ok, along, side, distance = pcall(function()
        local here = Vector3f.new()
        _vehicle:getLocalPos(_player:getX(), _player:getY(), _player:getZ(), here)
        local lengthways, sideways = here:z(), here:x()

        -- How far the player is from the vehicle's footprint, rather than from its
        -- centre: a truck's centre is three tiles from its own bumper, so a plain
        -- distance check would refuse the one place you would actually stand.
        --
        -- This is getClosestPointOnExtents' own arithmetic - clamp the local position
        -- into the extents box, measure what is left - done here in Lua because that
        -- method wants an org.joml.Vector2f and nothing in vanilla Lua ever builds
        -- one, so there is no evidence the class is exposed under that name. It skips
        -- the centre-of-mass shift the Java version applies, which is a couple of
        -- centimetres on the vehicles that ship with the game.
        local extents = _vehicle:getScript():getExtents()
        local overX = math.abs(sideways) - extents:x() / 2
        local overZ = math.abs(lengthways) - extents:z() / 2
        if overX < 0 then overX = 0 end
        if overZ < 0 then overZ = 0 end

        return lengthways, sideways, math.sqrt(overX * overX + overZ * overZ)
    end)
    if not ok or along == nil then return nil, nil end

    if distance == nil or distance > COOPPush.REACH then return nil, distance end
    if math.abs(along) < math.abs(side) * COOPPush.CONE then return nil, distance end

    if along > 0 then return COOPPush.FRONT, distance end
    return COOPPush.REAR, distance
end

-- Standing at the back means pushing the car forwards, standing at the hood means
-- pushing it backwards. +1 or -1 along the vehicle's own axis.
function COOPPush.signFor(_end)
    if _end == COOPPush.FRONT then return -1 end
    return 1
end

-- Is this vehicle moving faster than a push could have made it? Something else is
-- driving it - another player leaning on the far end, or a collision - and the answer
-- to a car going somewhere on its own is to let go of it, not to jog alongside.
function COOPPush.isRunaway(_vehicle)
    if _vehicle == nil then return true end

    local speed = 0
    pcall(function() speed = math.abs(_vehicle:getCurrentSpeedKmHour()) end)

    return speed > COOPPush.speedFor(_vehicle) * COOPPush.RUNAWAY
end

-- ---------------------------------------------------------------------------
-- may this be pushed at all
-- ---------------------------------------------------------------------------

-- Returns true, or false plus a translation key saying why not.
--
-- The judgement calls, and what a careful player would expect:
--
--   * A driver in the seat blocks it. They have the handbrake and the wheel; shoving a
--     car somebody is sitting in is how people get run over. Passengers are fine - you
--     can push a car with somebody asleep in the back. (This is also where vanilla
--     draws the line: authorizationClientCollide refuses to hand over the simulation
--     while a vehicle has a driver.)
--   * A running engine blocks it, for the same reason and because the car is already
--     under its own power.
--   * A missing wheel blocks it. A car on a bare hub does not roll, it drags, and the
--     refusal reads better than a car that silently will not move.
--   * A burnt or smashed wreck is fine. It still has wheels, and clearing a wreck off
--     your driveway is most of the reason to want this.
--   * A trailer already hitched to something is fine: the physics constraint drags the
--     whole rig along, which is what pushing a hitched trailer really does.
--   * The handbrake is not consulted, because B42 exposes no way to ask - BaseVehicle
--     has no handbrake getter at all, only a private sound update.
--   * Slopes do not come into it: a Build 42 level is flat, so the only thing resisting
--     the push is wheel friction.
function COOPPush.canPush(_vehicle, _player)
    if not COOPPush.isEnabled() then return false, nil end
    if _vehicle == nil or _player == nil then return false, nil end

    if _player:getVehicle() ~= nil then return false, nil end

    local okState, reason = pcall(function()
        if _vehicle:getDriver() ~= nil then return "UI_COOP_Push_HasDriver" end
        if _vehicle:isEngineRunning() then return "UI_COOP_Push_EngineOn" end
        if _vehicle:isAnyTireMissing() then return "UI_COOP_Push_NoTire" end
        return nil
    end)
    if okState and reason ~= nil then return false, reason end

    local which = COOPPush.endFor(_vehicle, _player)
    if which == nil then return false, "UI_COOP_Push_NotAtEnd" end

    return true, nil
end

-- ---------------------------------------------------------------------------
-- moving it
-- ---------------------------------------------------------------------------

-- One tick of push. _sign is +1 to roll the vehicle forwards, -1 backwards.
--
-- A plain proportional controller: shove hard while the vehicle is well below its
-- target speed, ease off as it gets there, stop entirely once it is at speed and let
-- friction do the rest. That keeps the result the same on a hatchback and on a van -
-- the force scales with the mass, so the acceleration does not.
--
-- Speed is read as an absolute value, exactly as vanilla's own ISStopVehicle does. A
-- vehicle that is somehow already rolling the other way therefore reads as "at speed"
-- and gets no push, which is the safe way to be wrong: you cannot push a car that is
-- moving away from you.
function COOPPush.push(_vehicle, _sign, _fx, _fy)
    if _vehicle == nil or _fx == nil then return false end

    local mass = COOPPush.massOf(_vehicle)
    local target = COOPPush.speedFor(_vehicle)
    if mass <= 0 or target <= 0 then return false end

    local speed = 0
    pcall(function() speed = math.abs(_vehicle:getCurrentSpeedKmHour()) end)

    if speed > target * COOPPush.RUNAWAY then return false end

    local effort = (target - speed) / target
    if effort <= 0 then return true end
    if effort > 1 then effort = 1 end

    local force = mass * COOPPush.MAX_ACCEL * effort

    local ok, err = pcall(function()
        -- Bullet's axes, not the world's: (world x, height, world y).
        --
        -- Built through the three-float constructor rather than new():set(x, y, z),
        -- because joml declares both set(float,float,float) and set(double,double,
        -- double) and there is no telling which one the Lua binding would pick; the
        -- three-argument constructor has no such twin.
        local impulse = Vector3f.new(_fx * _sign * force, 0, _fy * _sign * force)

        -- At the centre of mass, so the cross product that becomes the torque is zero
        -- and the vehicle rolls straight instead of slewing. A push applied at the
        -- corner of a bumper would steer it, which is not what the option promises.
        local relPos = Vector3f.new(0, 0, 0)

        -- A body Bullet has put to sleep ignores forces until it is woken. The other
        -- impulse entry point does this for itself; addImpulse does not.
        _vehicle:setPhysicsActive(true)

        -- addImpulse(impulse, relPos) - that order, confirmed against the bytecode.
        -- It holds one pending impulse which BaseVehicle.update() spends on the next
        -- tick, so this is called exactly once per tick: a second call before the
        -- engine has consumed the first cancels it outright.
        _vehicle:addImpulse(impulse, relPos)
    end)

    if not ok then
        COOP.log("push: " .. tostring(err))
        return false
    end

    if COOPPush.debug then
        COOP.log(string.format("push mass=%.0f target=%.1f speed=%.2f force=%.0f",
                mass, target, speed, force))
    end

    return true
end

-- Tells the engine that this player's client is the one simulating the vehicle, the
-- same way walking into a parked car does. Without it a multiplayer client's push
-- fights whatever the vehicle's current owner is sending, and the car judders instead
-- of rolling. Vanilla refuses to hand it over while somebody is driving, which is
-- exactly the case canPush already turned away.
function COOPPush.claim(_vehicle, _player)
    if _vehicle == nil or _player == nil then return end
    if not isClient() then return end

    pcall(function() _vehicle:authorizationClientCollide(_player) end)
end
