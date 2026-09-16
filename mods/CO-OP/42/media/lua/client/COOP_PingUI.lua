--
-- CO-OP - placing and showing pings.
--
-- The trigger is a real key binding (Options > Key bindings > [CO-OP] > Ping), so it can
-- be moved anywhere. It defaults to the middle mouse button, which nothing in the game
-- uses: no Lua file mentions onMiddleMouseDown and zombie/input/Mouse is the only class
-- in the jar that touches isMiddle*.
--
-- Mouse buttons are ordinary binding codes - Mouse.BTN_OFFSET (10000) plus the button
-- index, and vanilla binds Attack/Click to Mouse.LMB the same way - but the UI layer
-- only *routes* left and right clicks, and OnKeyPressed never fires for a mouse button.
-- So the binding is read and then dispatched two ways: a keyboard code goes through
-- OnKeyPressed, a mouse code is polled.
--
-- Polling reads Mouse.isButtonDown() and keeps its own "was it down last time" rather
-- than Mouse.isButtonPressed(). isButtonPressed is a one-frame edge (buttonDownStates vs
-- buttonPrevStates), and a poll driven by OnTick can easily land between two frames and
-- miss it. A level read plus our own edge is exact for anything longer than one poll,
-- which every human click is.
--
-- A ping shows up four ways at once, so it works whatever the viewer is doing:
--   * a blinking square marker on the ground (engine WorldMarkers, so no draw code)
--   * a homing arrow pointing at it from the screen edge while it is off-screen
--   * the pinger's name floating above the spot, and on the open world map
--   * a line in chat, for when you were looking at your inventory
--

if isServer() then return end

require "COOP_Common"
require "COOP_Ping"

-- Set to true to trace every ping and, more usefully, every click that was swallowed
-- because a window was under the cursor. The UI hit test is the one part of this that
-- can silently eat the whole feature.
COOPPing.debug = false

-- The vanilla map symbols: 64x64 and white, so they tint.
local ICON_PATH = "media/ui/LootableMaps/map_%s.png"

-- What a kind looks like. Only "spot" has no colour of its own: a plain ping is drawn in
-- the pinger's colour, so several people marking places stay apart. The rest mean the
-- same thing to everyone, so they are the same colour for everyone - a danger ping is
-- red whoever placed it.
local KIND_STYLE = {
    [COOPPing.SPOT]    = { icon = "exclamation" },
    [COOPPing.DANGER]  = { icon = "skull",         r = 1.00, g = 0.25, b = 0.20 },
    [COOPPing.PLAYER]  = { icon = "facehappy",     r = 1.00, g = 1.00, b = 1.00 },
    [COOPPing.VEHICLE] = { icon = "steeringwheel", r = 0.45, g = 0.70, b = 1.00 },
    [COOPPing.LOOT]    = { icon = "star",          r = 1.00, g = 0.85, b = 0.25 },
    [COOPPing.BODY]    = { icon = "facedead",      r = 0.75, g = 0.75, b = 0.80 },
}

local KIND_TEXT = {
    [COOPPing.SPOT] = "UI_COOP_Ping_Kind_Spot",
    [COOPPing.DANGER] = "UI_COOP_Ping_Kind_Danger",
    [COOPPing.PLAYER] = "UI_COOP_Ping_Kind_Player",
    [COOPPing.VEHICLE] = "UI_COOP_Ping_Kind_Vehicle",
    [COOPPing.LOOT] = "UI_COOP_Ping_Kind_Loot",
    [COOPPing.BODY] = "UI_COOP_Ping_Kind_Body",
}

local MARKER_SIZE = 0.75          -- grid square marker, in tiles
local LABEL_LIFT = 52             -- pixels above the pinged square
local MAP_ICON = 26               -- ping icon on the world map, in pixels
local MAP_PULSE = 8               -- how much it grows and shrinks
local FADE_MS = 1500              -- the tail end of a ping's life fades out

local pings = {}
local textures = {}
local lastRequest = nil

local function styleOf(_kind)
    return KIND_STYLE[_kind] or KIND_STYLE[COOPPing.SPOT]
end

local function iconFor(_kind)
    local name = styleOf(_kind).icon
    if textures[name] == nil then
        local ok, found = pcall(function() return getTexture(string.format(ICON_PATH, name)) end)
        textures[name] = (ok and found) or false
    end
    if textures[name] == false then return nil end
    return textures[name]
end

local function colourFor(_kind, _by)
    local style = styleOf(_kind)
    if style.r ~= nil then return style.r, style.g, style.b end
    return COOPPing.colourFor(_by)
end

-- ---------------------------------------------------------------------------
-- showing a ping
-- ---------------------------------------------------------------------------

-- The engine draws this one; it needs the square to be loaded, which it may not be
-- when the ping came off the world map, so it is retried until the chunk arrives.
local function attachMarker(_ping)
    local cell = getCell()
    if cell == nil then return end

    local square = cell:getGridSquare(_ping.x, _ping.y, _ping.z)
    if square == nil then return end

    pcall(function()
        _ping.marker = getWorldMarkers():addGridSquareMarker(square,
                _ping.r, _ping.g, _ping.b, true, MARKER_SIZE)
        _ping.marker:setDoBlink(true)
    end)
end

local function attachArrow(_ping)
    local player = getPlayer()
    if player == nil then return end

    pcall(function()
        -- the 7 argument form draws the vanilla "arrow_triangle", the same marker
        -- foraging uses to point at an icon you cannot see yet
        _ping.arrow = getWorldMarkers():addPlayerHomingPoint(player,
                _ping.x, _ping.y, _ping.r, _ping.g, _ping.b, 1.0)
    end)
end

local function detach(_ping)
    if _ping.marker ~= nil then
        pcall(function() _ping.marker:remove() end)
        _ping.marker = nil
    end
    if _ping.arrow ~= nil then
        pcall(function() _ping.arrow:remove() end)
        _ping.arrow = nil
    end
end

-- For when you were looking at your inventory. COOP.sayInChat carries the stand-in
-- ChatMessage; the ping's own colour makes whose it is readable at a glance.
local function sayInChat(_ping)
    if COOP.option("PingChatLine", true) == false then return end

    local kind = getText(KIND_TEXT[_ping.kind] or KIND_TEXT[COOPPing.SPOT])
    COOP.sayInChat(getText("UI_COOP_Ping_Chat", _ping.by, kind, _ping.x, _ping.y),
            _ping.r, _ping.g, _ping.b)
end

function COOPPing.show(_x, _y, _z, _kind, _by)
    if not COOP.featureEnabled(COOP.F_PINGS) then return end

    local kind = _kind or COOPPing.SPOT
    local by = tostring(_by or "?")
    local r, g, b = colourFor(kind, by)
    local now = getTimestampMs()

    local ping = {
        x = _x, y = _y, z = _z,
        kind = kind, by = by,
        r = r, g = g, b = b,
        born = now,
        expires = now + COOPPing.durationMs(),
    }

    attachMarker(ping)
    attachArrow(ping)
    table.insert(pings, ping)
    sayInChat(ping)

    pcall(function() getSoundManager():playUISound("UIActivateButton") end)

    if COOPPing.debug then
        COOP.log("ping from " .. by .. " at " .. _x .. "," .. _y .. "," .. _z
                .. " (" .. kind .. ") marker=" .. tostring(ping.marker ~= nil)
                .. " arrow=" .. tostring(ping.arrow ~= nil))
    end
end

function COOPPing.clear()
    for _, ping in ipairs(pings) do detach(ping) end
    pings = {}
end

-- How solid a ping should be drawn right now: full, then fading out at the end.
local function alphaOf(_ping, _now)
    local left = _ping.expires - _now
    if left >= FADE_MS then return 1.0 end
    if left <= 0 then return 0.0 end
    return left / FADE_MS
end

local function update()
    if #pings == 0 then return end

    local now = getTimestampMs()
    local alive = {}

    for _, ping in ipairs(pings) do
        if now >= ping.expires then
            detach(ping)
        else
            -- the square may only have loaded after the ping arrived
            if ping.marker == nil then attachMarker(ping) end
            if ping.arrow == nil then attachArrow(ping) end
            table.insert(alive, ping)
        end
    end

    pings = alive
end

-- ---------------------------------------------------------------------------
-- the name floating over the spot
--
-- Drawn straight from OnPostUIDraw rather than from a full screen UI element: an
-- element that large would have to be told not to consume mouse events and would sit
-- in the way of everything, and getTextManager() draws fine from this event - the
-- Last Stand and tutorial overlays do exactly this.
-- ---------------------------------------------------------------------------

local function drawLabels()
    if #pings == 0 then return end
    -- the map covers the screen and draws its own pings
    if ISWorldMap ~= nil and ISWorldMap.instance ~= nil then return end

    local player = getPlayer()
    if player == nil then return end

    local playerNum = player:getPlayerNum()
    local width = getCore():getScreenWidth()
    local height = getCore():getScreenHeight()
    local now = getTimestampMs()

    for _, ping in ipairs(pings) do
        local ok, sx, sy = pcall(function()
            return isoToScreenX(playerNum, ping.x + 0.5, ping.y + 0.5, ping.z),
                   isoToScreenY(playerNum, ping.x + 0.5, ping.y + 0.5, ping.z)
        end)
        if ok and sx ~= nil and sy ~= nil
                and sx > -width and sx < width * 2 and sy > -height and sy < height * 2 then
            getTextManager():DrawStringCentre(UIFont.Small, sx, sy - LABEL_LIFT,
                    ping.by, ping.r, ping.g, ping.b, alphaOf(ping, now))
        end
    end
end

-- ---------------------------------------------------------------------------
-- what is under the cursor
-- ---------------------------------------------------------------------------

local function classify(_x, _y, _z)
    local picker = IsoObjectPicker.Instance
    if picker == nil then return COOPPing.SPOT end

    local mx, my = getMouseX(), getMouseY()

    local target = nil
    pcall(function() target = picker:PickTarget(mx, my) end)
    if target ~= nil then
        if instanceof(target, "IsoZombie") then return COOPPing.DANGER end
        if instanceof(target, "IsoPlayer") then return COOPPing.PLAYER end
    end

    local vehicle = nil
    pcall(function() vehicle = picker:PickVehicle(mx, my) end)
    if vehicle ~= nil then return COOPPing.VEHICLE end

    local corpse = nil
    pcall(function() corpse = picker:PickCorpse(mx, my) end)
    if corpse ~= nil then return COOPPing.BODY end

    -- anything worth walking over for: loose items, or something with a container
    local loot = false
    pcall(function()
        local square = getCell():getGridSquare(_x, _y, _z)
        if square == nil then return end

        local onFloor = square:getWorldObjects()
        if onFloor ~= nil and onFloor:size() > 0 then loot = true; return end

        local objects = square:getObjects()
        if objects == nil then return end
        for i = 0, objects:size() - 1 do
            local object = objects:get(i)
            if object ~= nil and object:getContainerCount() > 0 then loot = true; return end
        end
    end)
    if loot then return COOPPing.LOOT end

    return COOPPing.SPOT
end

-- ---------------------------------------------------------------------------
-- placing a ping
-- ---------------------------------------------------------------------------

function COOPPing.request(_x, _y, _z, _kind)
    if not COOP.featureEnabled(COOP.F_PINGS) then return end

    local player = getPlayer()
    if player == nil then return end

    local x, y, z, kind = COOPPing.sanitise({ x = _x, y = _y, z = _z, kind = _kind })
    if x == nil then return end

    -- the server enforces this too; this only keeps a held button off the channel
    local now = getTimestampMs()
    if lastRequest ~= nil and now - lastRequest < COOPPing.intervalMs() then return end
    lastRequest = now

    if isClient() then
        sendClientCommand(player, COOPPing.MODULE, COOPPing.COMMAND,
                { x = x, y = y, z = z, kind = kind })
    else
        -- single player: nobody to ask
        COOPPing.show(x, y, z, kind, COOP.playerName(player))
    end
end

local function pingFromWorld()
    local player = getPlayer()
    if player == nil or player:isDead() then return end

    local z = math.floor(player:getZ())
    local ok, x, y = pcall(function()
        local playerNum = player:getPlayerNum()
        return screenToIsoX(playerNum, getMouseX(), getMouseY(), z),
               screenToIsoY(playerNum, getMouseX(), getMouseY(), z)
    end)
    if not ok or x == nil or y == nil then return end

    COOPPing.request(x, y, z, classify(math.floor(x), math.floor(y), z))
end

-- The map is flat, so a ping placed on it lands on the floor the pinger is standing on -
-- which is what they meant if they are on a roof, and the ground otherwise.
local function pingFromMap(_map)
    if _map:isMouseOverChild() then return end

    local mx, my = _map:getMouseX(), _map:getMouseY()
    if mx < 0 or my < 0 or mx > _map:getWidth() or my > _map:getHeight() then return end

    local player = getPlayer()
    if player == nil then return end

    local ok, x, y = pcall(function()
        return _map.mapAPI:uiToWorldX(mx, my), _map.mapAPI:uiToWorldY(mx, my)
    end)
    if not ok or x == nil or y == nil then return end

    COOPPing.request(x, y, math.floor(player:getZ()), COOPPing.SPOT)
end

-- Is the cursor over a window rather than the world? Only asked on the click itself,
-- so walking the root elements costs nothing.
local function mouseOverUI()
    local ok, over = pcall(function()
        local ui = UIManager.getUI()
        if ui == nil then return false end

        local mx, my = getMouseX(), getMouseY()
        for i = 0, ui:size() - 1 do
            local element = ui:get(i)
            if element ~= nil and element:isReallyVisible()
                    and element:isConsumeMouseEvents() and element:isPointOver(mx, my) then
                if COOPPing.debug then
                    COOP.log("ping swallowed by a window at "
                            .. tostring(element:getAbsoluteX()) .. "," .. tostring(element:getAbsoluteY())
                            .. " sized " .. tostring(element:getWidth()) .. "x" .. tostring(element:getHeight()))
                end
                return true
            end
        end
        return false
    end)
    return (not ok) or over == true
end

-- ---------------------------------------------------------------------------
-- the trigger
-- ---------------------------------------------------------------------------

local worldDown = false
local mapDown = false

local function boundKey()
    local ok, key = pcall(function() return getCore():getKey(COOPKeys.PING) end)
    if ok and type(key) == "number" then return key end
    return Mouse.MMB
end

-- true/false while the binding is a mouse button, nil when it is a keyboard key (which
-- arrives through OnKeyPressed instead) or unbound.
local function boundButtonDown()
    local key = boundKey()
    if key < Mouse.BTN_OFFSET then return nil end

    local ok, down = pcall(function() return Mouse.isButtonDown(key - Mouse.BTN_OFFSET) end)
    if not ok then return nil end
    return down == true
end

local function pollWorld()
    local down = boundButtonDown()
    if down == nil then worldDown = false; return end

    local pressed = down and not worldDown
    worldDown = down
    if not pressed then return end

    -- the world map is a full screen element and handles its own clicks
    if ISWorldMap ~= nil and ISWorldMap.instance ~= nil then return end
    if mouseOverUI() then return end

    pingFromWorld()
end

local function pollMap(_map)
    local down = boundButtonDown()
    if down == nil then mapDown = false; return end

    local pressed = down and not mapDown
    mapDown = down
    if not pressed then return end

    pingFromMap(_map)
end

local function onKeyPressed(_key)
    if getPlayer() == nil then return end
    if not getCore():isKey(COOPKeys.PING, _key) then return end

    local map = (ISWorldMap ~= nil) and ISWorldMap.instance or nil
    if map ~= nil then
        pingFromMap(map)
    elseif not mouseOverUI() then
        pingFromWorld()
    end
end

-- ---------------------------------------------------------------------------
-- the map
-- ---------------------------------------------------------------------------

local function renderOnMap(_map)
    if #pings == 0 then return end

    local now = getTimestampMs()

    for _, ping in ipairs(pings) do
        local ok, ux, uy = pcall(function()
            return _map.mapAPI:worldToUIX(ping.x + 0.5, ping.y + 0.5),
                   _map.mapAPI:worldToUIY(ping.x + 0.5, ping.y + 0.5)
        end)
        if ok and ux ~= nil and uy ~= nil
                and ux > -MAP_ICON and uy > -MAP_ICON
                and ux < _map:getWidth() + MAP_ICON and uy < _map:getHeight() + MAP_ICON then
            local alpha = alphaOf(ping, now)
            -- a slow pulse, so a ping stands out from the drawn symbols around it
            local pulse = MAP_PULSE * (1 - math.abs(((now - ping.born) % 1200) / 600 - 1))
            local size = MAP_ICON + pulse
            local icon = iconFor(ping.kind)

            if icon ~= nil then
                _map:drawTextureScaled(icon, ux - size / 2, uy - size / 2, size, size,
                        alpha, ping.r, ping.g, ping.b)
            end
            _map:drawTextCentre(ping.by, ux, uy + size / 2 + 2,
                    ping.r, ping.g, ping.b, alpha, UIFont.Small)
        end
    end
end

-- ---------------------------------------------------------------------------
-- hooks
-- ---------------------------------------------------------------------------

local installed = {}

local function hook(_class, _name, _key, _make)
    if _class == nil then return false end
    if installed[_key] ~= nil and _class[_name] == installed[_key] then return false end

    local original = _class[_name]
    if original == nil then return false end

    local wrapper = _make(original)
    _class[_name] = wrapper
    installed[_key] = wrapper
    return true
end

local function install()
    -- One hook does both jobs: ISWorldMap:render runs every frame the map is up, which
    -- is also the only time a click should mean "ping this map position".
    local any = hook(ISWorldMap, "render", "mapRender", function(_original)
        return function(self)
            _original(self)
            pcall(pollMap, self)
            pcall(renderOnMap, self)
        end
    end)

    if any then COOP.log("pings ready") end
end

local function onServerCommand(_module, _command, _args)
    if _module ~= COOPPing.MODULE or _command ~= COOPPing.COMMAND then return end

    local x, y, z, kind = COOPPing.sanitise(_args)
    if x == nil then return end

    COOPPing.show(x, y, z, kind, _args.by)
end

install()
Events.OnGameBoot.Add(install)
Events.OnGameStart.Add(install)

Events.OnServerCommand.Add(onServerCommand)
Events.OnKeyPressed.Add(onKeyPressed)
Events.OnTick.Add(pollWorld)
Events.OnTick.Add(update)
Events.OnPostUIDraw.Add(drawLabels)

-- markers belong to a world that is about to go away
Events.OnPlayerDeath.Add(COOPPing.clear)
