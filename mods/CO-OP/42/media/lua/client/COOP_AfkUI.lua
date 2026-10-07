--
-- CO-OP - AFK: the sidebar button, the countdown, the badge, and keeping other people's
-- hands off an AFK player.
--
-- The button sits at the bottom of the vanilla sidebar (the column with the heart).
-- Pressing it starts a countdown of AfkDelay seconds; the player has to do nothing at
-- all for that long - not move, not queue an action, not aim - or the countdown is
-- dropped. Once it runs out the server is asked to freeze them. From then on anything
-- the player does ends it at once.
--
-- Deciding "the player did something" is the client's job, because only the client
-- sees the input; the freeze and the list everyone reads are the server's
-- (COOP_AfkServer.lua). In single player both halves run here.
--

if isServer() then return end

require "COOP_Afk"

COOPAfkUI = COOPAfkUI or {}

local OFF, ARMING, ON = "off", "arming", "on"
local state = OFF
local armStartMs = 0
local anchor = nil

-- Further than this from the spot is walking, not the idle animation swaying.
local MOVE_LIMIT = 0.3

local synced = false
local nextSyncMs = 0
local SYNC_RETRY_MS = 10000

local ICON_SIZES = { 48, 64, 80, 96, 128 }
local BADGE_TEXTURE = "media/ui/COOP_AfkBadge.png"
-- How far above the feet the badge sits, in screen pixels at zoom 1 - a little above
-- the foraging icon (140) so it clears the name tag and halo text.
local BADGE_LIFT = 165

local function me()
    return getSpecificPlayer(0)
end

local function myName()
    local player = me()
    if player == nil then return nil end
    return COOP.playerName(player)
end

local function halo(_player, _good, _text)
    pcall(function()
        if _good then HaloTextHelper.addGoodText(_player, _text)
        else HaloTextHelper.addBadText(_player, _text) end
    end)
end

local function request(_command)
    local player = me()
    if player == nil then return end

    if isClient() then
        sendClientCommand(player, COOPAfk.MODULE, _command, {})
        return
    end

    -- Single player: no round trip, call the authority directly.
    if COOPAfkServer == nil then return end
    if _command == COOPAfk.CMD_ON then
        COOPAfkServer.start(player)
    elseif _command == COOPAfk.CMD_OFF then
        COOPAfkServer.stopPlayer(player, COOPAfk.R_BACK)
    end
end

-- ---------------------------------------------------------------------------
-- has the player done anything
-- ---------------------------------------------------------------------------

local function call(_object, _method)
    local ok, value = pcall(function() return _object[_method](_object) end)
    if ok then return value end
    return nil
end

local function snapshotPosition(_player)
    return {
        x = _player:getX(), y = _player:getY(), z = _player:getZ(),
        vehicle = call(_player, "getVehicle"),
        sitting = call(_player, "isSitOnGround") == true,
    }
end

-- A reason string when the player is doing something, nil when they are idle.
local function activity(_player)
    if call(_player, "isDead") then return "dead" end
    if call(_player, "isAsleep") then return "asleep" end

    local queue = ISTimedActionQueue and ISTimedActionQueue.queues
            and ISTimedActionQueue.queues[_player]
    if queue ~= nil and queue.queue ~= nil and #queue.queue > 0 then return "action" end
    local actions = call(_player, "getCharacterActions")
    if actions ~= nil and not actions:isEmpty() then return "action" end

    if call(_player, "isAiming") then return "aim" end
    if call(_player, "isPerformingHostileAnimation") then return "attack" end

    if anchor ~= nil then
        if call(_player, "getVehicle") ~= anchor.vehicle then return "vehicle" end
        if (call(_player, "isSitOnGround") == true) ~= anchor.sitting then return "sit" end
        if math.floor(_player:getZ()) ~= math.floor(anchor.z) then return "moved" end
        local dx, dy = _player:getX() - anchor.x, _player:getY() - anchor.y
        if dx * dx + dy * dy > MOVE_LIMIT * MOVE_LIMIT then return "moved" end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- auto-drink
--
-- With auto-drink on, a thirsty character sips from a bottle by themselves - straight
-- from Java, no timed action - and with thirst held above the threshold an AFK player
-- would drink their water away. The AutoDrink Lua hook skips the engine's auto-drink
-- whenever it has *any* callback (vanilla uses exactly this to keep a water transfer
-- from being drunk), so one is registered while the countdown runs or the player is
-- AFK, and removed after. Single player only: in multiplayer auto-drink runs on the
-- server, where a hook would stop it for everybody, so the server switches off that
-- one player's auto-drink flag instead.
-- ---------------------------------------------------------------------------

local autoDrinkHooked = false
local function blockAutoDrink(_character) end

local function setAutoDrinkBlocked(_blocked)
    if isClient() then return end
    if _blocked == autoDrinkHooked then return end
    pcall(function()
        if _blocked then Hook.AutoDrink.Add(blockAutoDrink)
        else Hook.AutoDrink.Remove(blockAutoDrink) end
    end)
    autoDrinkHooked = _blocked
end

-- ---------------------------------------------------------------------------
-- going and coming back
-- ---------------------------------------------------------------------------

function COOPAfkUI.isArming()
    return state == ARMING
end

function COOPAfkUI.secondsLeft()
    if state ~= ARMING then return 0 end
    local left = COOPAfk.delaySeconds() - (getTimestampMs() - armStartMs) / 1000
    return math.max(0, math.ceil(left))
end

local function cancelArming(_reason)
    state = OFF
    anchor = nil
    setAutoDrinkBlocked(false)
    local player = me()
    if player ~= nil then halo(player, false, getText("UI_COOP_Afk_Cancelled")) end
end

local function startArming()
    local player = me()
    if player == nil then return end

    local busy = activity(player)
    if busy == "asleep" then
        halo(player, false, getText("UI_COOP_Afk_Asleep"))
        return
    elseif busy ~= nil then
        halo(player, false, getText("UI_COOP_Afk_Busy"))
        return
    end

    state = ARMING
    armStartMs = getTimestampMs()
    anchor = snapshotPosition(player)
    setAutoDrinkBlocked(true)
    halo(player, true, getText("UI_COOP_Afk_Arming", tostring(COOPAfk.delaySeconds())))
end

local function goAfk()
    local player = me()
    if player == nil then return end
    -- the state goes first: in single player the answer comes back inside request()
    state = ON
    anchor = snapshotPosition(player)
    request(COOPAfk.CMD_ON)
end

local function comeBack()
    if state ~= ON then return end
    state = OFF
    anchor = nil
    setAutoDrinkBlocked(false)
    request(COOPAfk.CMD_OFF)
end

function COOPAfkUI.onButton(_target, _button)
    if not COOPAfk.isEnabled() then return end
    if state == OFF then
        startArming()
    elseif state == ARMING then
        cancelArming()
    else
        comeBack()
    end
end

-- The server's word on who is AFK - for us, a confirmation or the reason it ended.
function COOPAfkUI.onState(_args)
    if _args == nil or _args.name == nil then return end
    local name = tostring(_args.name)

    if _args.on then COOPAfk.names[name] = true else COOPAfk.names[name] = nil end

    local player = me()
    if player ~= nil and name == myName() then
        if _args.on then
            if state == OFF then
                -- we already came back while the request was in flight
                request(COOPAfk.CMD_OFF)
            else
                state = ON
                halo(player, true, getText("UI_COOP_Afk_On"))
            end
            return
        end

        local wasOn = state ~= OFF
        state = OFF
        anchor = nil
        setAutoDrinkBlocked(false)

        local reason = _args.reason
        if reason == COOPAfk.R_HURT then
            halo(player, false, getText("UI_COOP_Afk_Hurt"))
        elseif reason == COOPAfk.R_REFUSED then
            halo(player, false, getText("UI_COOP_Afk_Refused"))
        elseif wasOn or reason == COOPAfk.R_BACK then
            halo(player, true, getText("UI_COOP_Afk_Back"))
        end
        return
    end

    -- somebody else: a line in chat, so the others know why nobody answers
    if not isClient() then return end
    local colour = { 1, 0.8, 0.3 }
    if COOPPing ~= nil and COOPPing.colourFor ~= nil then
        local ok, r, g, b = pcall(COOPPing.colourFor, name)
        if ok and r ~= nil then colour = { r, g, b } end
    end
    local key = _args.on and "UI_COOP_Afk_ChatOn" or "UI_COOP_Afk_ChatOff"
    COOP.sayInChat(getText(key, name), colour[1], colour[2], colour[3])
end

local function onServerCommand(_module, _command, _args)
    if _module ~= COOPAfk.MODULE then return end

    if _command == COOPAfk.CMD_STATE then
        COOPAfkUI.onState(_args)
    elseif _command == COOPAfk.CMD_SYNC then
        synced = true
        for name in pairs(COOPAfk.names) do COOPAfk.names[name] = nil end
        if _args ~= nil and _args.names ~= nil then
            for name, on in pairs(_args.names) do
                if on then COOPAfk.names[tostring(name)] = true end
            end
        end
    end
end

Events.OnServerCommand.Add(onServerCommand)

-- ---------------------------------------------------------------------------
-- the sidebar button
--
-- Not a wrap of ISEquippedItem:initialise: the sidebar is thrown away and rebuilt
-- whenever the sidebar size option changes (checkSidebarSizeOption), and it may well
-- exist before this file's hooks install. So every few ticks the current sidebar is
-- asked whether it carries our button, and given one if not. It is a plain ISButton
-- (Type "ISButton") because shrinkWrap only measures children of that type.
-- ---------------------------------------------------------------------------

local function iconSize(_width)
    local best = ICON_SIZES[1]
    for _, size in ipairs(ICON_SIZES) do
        if math.abs(size - _width) < math.abs(best - _width) then best = size end
    end
    return best
end

local function renderButton(_self)
    local on = state ~= OFF
    if _self.coopOn ~= on then
        _self.coopOn = on
        _self:setImage(on and _self.coopIconOn or _self.coopIconOff)
    end

    -- the countdown pulses the icon and prints the seconds beside it, the way the
    -- PvP safety button prints its own countdown
    if state == ARMING then
        _self.textureColor.a = 0.55 + 0.45 * math.abs(math.sin(getTimestampMs() / 250))
    else
        _self.textureColor.a = 1
    end

    ISButton.render(_self)

    if state == ARMING then
        local text = tostring(COOPAfkUI.secondsLeft())
        local font = UIFont.Medium
        local tw = getTextManager():MeasureStringX(font, text)
        local th = getTextManager():getFontHeight(font)
        _self:drawText(text, _self:getWidth() - tw - 2, _self:getHeight() - th, 1, 0.85, 0.3, 1, font)
    end
end

local function addButton(_bar)
    local width = _bar.healthBtn:getWidth()
    local height = _bar.healthBtn:getHeight()

    local bottom = 0
    for _, child in pairs(_bar:getChildren()) do
        if child.Type == "ISButton" then bottom = math.max(bottom, child:getBottom()) end
    end

    local size = iconSize(width)
    local btn = ISButton:new(0, bottom + 15, width, height, "", COOPAfkUI, COOPAfkUI.onButton)
    btn.coopIconOff = getTexture("media/ui/COOP_Afk_Off_" .. size .. ".png")
    btn.coopIconOn = getTexture("media/ui/COOP_Afk_On_" .. size .. ".png")
    btn:setImage(btn.coopIconOff)
    btn.internal = "COOP_AFK"
    btn:initialise()
    btn:instantiate()
    btn:setDisplayBackground(false)
    btn:ignoreWidthChange()
    btn:ignoreHeightChange()
    btn.render = renderButton
    _bar:addChild(btn)
    _bar:addMouseOverToolTipItem(btn, getText("UI_COOP_Afk_Tooltip", tostring(COOPAfk.delaySeconds())))
    _bar.coopAfkBtn = btn
    _bar:shrinkWrap()
end

local function ensureButton()
    local data = getPlayerData and getPlayerData(0)
    local bar = data and data.equipped
    if bar == nil or bar.healthBtn == nil then return end

    local enabled = COOPAfk.isEnabled() and getCore():getGameMode() ~= "Tutorial"
    if bar.coopAfkBtn ~= nil then
        if bar.coopAfkBtn:isVisible() ~= enabled then bar.coopAfkBtn:setVisible(enabled) end
        return
    end
    if enabled then addButton(bar) end
end

-- ---------------------------------------------------------------------------
-- the tick: the countdown, coming back, the button, the first sync
-- ---------------------------------------------------------------------------

local buttonTicks = 0

local function onTick()
    buttonTicks = buttonTicks + 1
    if buttonTicks >= 30 then
        buttonTicks = 0
        pcall(ensureButton)
    end

    if isClient() and not synced then
        local now = getTimestampMs()
        if now >= nextSyncMs and me() ~= nil then
            nextSyncMs = now + SYNC_RETRY_MS
            sendClientCommand(me(), COOPAfk.MODULE, COOPAfk.CMD_REQUEST_SYNC, {})
        end
    end

    if state == OFF then return end

    local player = me()
    if player == nil then state = OFF; setAutoDrinkBlocked(false); return end

    if not COOPAfk.isEnabled() then
        if state == ARMING then cancelArming() else comeBack() end
        return
    end

    local busy = activity(player)
    if state == ARMING then
        if busy ~= nil then
            cancelArming()
        elseif getTimestampMs() - armStartMs >= COOPAfk.delaySeconds() * 1000 then
            goAfk()
        end
    elseif busy ~= nil then
        comeBack()
    end
end

Events.OnTick.Add(onTick)

local function onCreatePlayer(_playerNum)
    if _playerNum ~= 0 then return end
    state = OFF
    anchor = nil
    setAutoDrinkBlocked(false)
end

Events.OnCreatePlayer.Add(onCreatePlayer)

-- ---------------------------------------------------------------------------
-- the badge over the head
--
-- Drawn from OnPostUIDraw like the ping labels, for every AFK player this client can
-- see, including the local one.
-- ---------------------------------------------------------------------------

local badgeTexture = nil

local function drawBadge(_playerNum, _player, _font, _text, _tw, _th, _zoom)
    local sx = isoToScreenX(_playerNum, _player:getX(), _player:getY(), _player:getZ())
    local sy = isoToScreenY(_playerNum, _player:getX(), _player:getY(), _player:getZ())
            - BADGE_LIFT / _zoom
    local padX, padY = 6, 1
    local w, h = _tw + padX * 2, _th + padY * 2

    -- SpriteRenderer has no 9-argument render: the colour form ends in a Consumer, and
    -- Kahlua picks an overload by argument count, so the nil has to be passed. (Vanilla's
    -- one 9-argument call, in GridSquareSelector.lua, fails the same way.) Should that
    -- ever throw, the pill is given up for good rather than failing every frame.
    local drawn = false
    if badgeTexture then
        drawn = pcall(function()
            getRenderer():render(badgeTexture, sx - w / 2, sy - h / 2, w, h, 0, 0, 0, 0.65, nil)
        end)
        if not drawn then badgeTexture = false end
    end
    if not drawn then
        getTextManager():DrawStringCentre(_font, sx + 1, sy - _th / 2 + 1, _text, 0, 0, 0, 1)
    end
    getTextManager():DrawStringCentre(_font, sx, sy - _th / 2, _text, 1, 0.8, 0.3, 1)
end

local function drawBadges()
    if COOPAfk.isEmpty(COOPAfk.names) then return end
    if not COOPAfk.isEnabled() then return end
    if ISWorldMap ~= nil and ISWorldMap.instance ~= nil then return end

    local viewer = me()
    if viewer == nil then return end
    local playerNum = viewer:getPlayerNum()

    if badgeTexture == nil then badgeTexture = getTexture(BADGE_TEXTURE) or false end

    local font = UIFont.Small
    local text = getText("UI_COOP_Afk_Badge")
    local tw = getTextManager():MeasureStringX(font, text)
    local th = getTextManager():getFontHeight(font)
    local zoom = getCore():getZoom(playerNum)
    if zoom == nil or zoom <= 0 then zoom = 1 end

    -- the online list on a client is not promised to hold the local player, so the
    -- viewer is added by hand and the two are de-duplicated
    local seen = {}
    local function consider(_player)
        if _player == nil or seen[_player] then return end
        seen[_player] = true
        if not COOPAfk.isAfkName(COOP.playerName(_player)) then return end
        if _player ~= viewer then
            -- an admin in ghost mode stays unseen, and someone the viewer cannot see
            -- (behind a wall, out of the light) is not drawn through it
            if call(_player, "isInvisible") then return end
            local ok, alpha = pcall(function() return _player:getAlpha(playerNum) end)
            if ok and type(alpha) == "number" and alpha < 0.1 then return end
        end
        pcall(drawBadge, playerNum, _player, font, text, tw, th, zoom)
    end

    consider(viewer)
    COOPAfk.eachPlayer(consider)
end

Events.OnPostUIDraw.Add(drawBadges)

-- ---------------------------------------------------------------------------
-- hands off an AFK player
--
-- Every vanilla action done *to* another player - bandaging, stitching, splinting,
-- disinfecting, the medical check, waking them - carries that player as otherPlayer,
-- and every one is queued through ISTimedActionQueue.add. So that one function is
-- the chokepoint: an action aimed at an AFK player is turned away with a note, and an
-- action of our own while the countdown runs or while AFK ends it on the spot, rather
-- than a tick later. Returning nil is what vanilla's own refusals (asleep, dragging a
-- corpse) already do, so callers cope with it. Trading does not go through the queue,
-- so its menu entry is checked on its own.
-- ---------------------------------------------------------------------------

local queueInstalled = nil
local tradeInstalled = nil

local function targetOf(_action)
    local other = _action.otherPlayer
    if other ~= nil and other ~= _action.character and instanceof(other, "IsoPlayer") then
        return other
    end
    return nil
end

local function refuseFor(_character, _other)
    local name = call(_other, "getDisplayName") or COOP.playerName(_other)
    halo(_character, false, getText("UI_COOP_Afk_IsAfk", tostring(name)))
end

local function install()
    if ISTimedActionQueue ~= nil and ISTimedActionQueue.add ~= nil
            and (queueInstalled == nil or ISTimedActionQueue.add ~= queueInstalled) then
        local original = ISTimedActionQueue.add
        queueInstalled = function(action)
            if action ~= nil and not action.ignoreAction then
                local other = targetOf(action)
                if other ~= nil and COOPAfk.isAfk(other) then
                    refuseFor(action.character, other)
                    return nil
                end
                if action.character ~= nil and action.character == me() and state ~= OFF then
                    if state == ARMING then cancelArming() else comeBack() end
                end
            end
            return original(action)
        end
        ISTimedActionQueue.add = queueInstalled
        COOP.log("AFK installed")
    end

    if ISWorldObjectContextMenu ~= nil and ISWorldObjectContextMenu.onTrade ~= nil
            and (tradeInstalled == nil or ISWorldObjectContextMenu.onTrade ~= tradeInstalled) then
        local original = ISWorldObjectContextMenu.onTrade
        tradeInstalled = function(worldobjects, player, otherPlayer)
            if otherPlayer ~= nil and COOPAfk.isAfk(otherPlayer) then
                refuseFor(player, otherPlayer)
                return
            end
            return original(worldobjects, player, otherPlayer)
        end
        ISWorldObjectContextMenu.onTrade = tradeInstalled
    end
end

Events.OnGameBoot.Add(install)
Events.OnGameStart.Add(install)
Events.OnInitGlobalModData.Add(install)
