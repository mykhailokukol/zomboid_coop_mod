--
-- CO-OP - the boombox: its window, what this client knows is playing, and the bridge to
-- the Boombox speaker running next to the game.
--
-- Right-clicking a boombox in the inventory opens its window: a link box, Play, Pause and
-- Stop, what is playing and how far in, and the volume bar the radio and TV windows use.
-- Only a boombox in your hands plays; the window says so when it is not.
--
-- Every boombox the server says is playing is kept in COOPBoomboxUI.boxes. A few times a
-- second this client works out how loud each one is where its players stand and writes
-- the list to Zomboid/Lua/coop_boombox.txt for the speaker; once a second it reads what
-- the speaker wrote back (COOP_Boombox.lua has the two files). The title and length of a
-- track come from the speaker of the player holding the boombox, who passes them on to
-- the server for everyone else.
--

if isServer() then return end

require "ISUI/ISCollapsableWindow"
require "RadioCom/ISUIRadio/ISVolumeBar"
require "COOP_Boombox"

COOPBoomboxUI = COOPBoomboxUI or {}

-- item id -> the server's payload plus recvMs, the local time it arrived
COOPBoomboxUI.boxes = COOPBoomboxUI.boxes or {}

local WRITE_MS = 250                -- while something can be heard
local HEARTBEAT_MS = 1000           -- otherwise, so the speaker knows the game is up
local READ_MS = 1000
local SYNC_RETRY_MS = 5000
local SPEAKER_STALE_MS = 5000

local lastWrite = 0
local heardLast = false
local lastRead = 0
local synced = false
local nextSync = 0

-- what the speaker last wrote back
local speaker = { alive = 0, meta = {}, errors = {} }
-- item id -> what was last passed on to the server as meta / the url announced in chat
local metaSent = {}
local announced = {}

local function now() return getTimestampMs() end

-- To the server, or in single player straight to the authority in this Lua state.
function COOPBoomboxUI.send(_player, _command, _args)
    if isClient() then
        sendClientCommand(_player, COOPBoombox.MODULE, _command, _args or {})
    elseif COOPBoomboxServer ~= nil then
        COOPBoomboxServer.handle(_player, _command, _args or {})
    end
end

function COOPBoomboxUI.speakerRunning()
    return now() - speaker.alive < SPEAKER_STALE_MS
end

function COOPBoomboxUI.speakerError(_id, _url)
    local err = speaker.errors[_id]
    if err ~= nil and err.url == _url then return err.text end
    return nil
end

-- ---------------------------------------------------------------------------
-- from the server
-- ---------------------------------------------------------------------------

local function store(_args)
    local id = tonumber(_args.id)
    if id == nil then return end
    local box = {}
    for k, v in pairs(_args) do box[k] = v end
    box.id = id
    box.recvMs = now()
    local old = COOPBoomboxUI.boxes[id]
    if old == nil or old.url ~= box.url then
        metaSent[id] = nil
        announced[id] = nil
    end
    COOPBoomboxUI.boxes[id] = box
end

local REASONS = {
    hands = "UI_COOP_Boombox_NotHeld",
    url = "UI_COOP_Boombox_BadLink",
}

function COOPBoomboxUI.onServerCommand(_module, _command, _args)
    if _module ~= COOPBoombox.MODULE or _args == nil then return end
    if _command == COOPBoombox.CMD_STATE then
        store(_args)
    elseif _command == COOPBoombox.CMD_GONE then
        local id = tonumber(_args.id)
        if id ~= nil then COOPBoomboxUI.boxes[id] = nil end
    elseif _command == COOPBoombox.CMD_ALL then
        synced = true
        COOPBoomboxUI.boxes = {}
        if _args.boxes ~= nil then
            for _, box in pairs(_args.boxes) do store(box) end
        end
    elseif _command == COOPBoombox.CMD_RESULT then
        local key = REASONS[_args.reason]
        if key ~= nil then COOP.sayInChat(getText(key)) end
    end
end

Events.OnServerCommand.Add(COOPBoomboxUI.onServerCommand)

Events.OnGameStart.Add(function()
    COOPBoomboxUI.boxes = {}
    synced = not isClient()
    nextSync = 0
end)

-- ---------------------------------------------------------------------------
-- the speaker bridge
-- ---------------------------------------------------------------------------

local function localListeners()
    local list = {}
    for n = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(n)
        if player ~= nil and not player:isDead() then table.insert(list, player) end
    end
    return list
end

local function gameVolume()
    local ok, value = pcall(function() return getCore():getOptionSoundVolume() end)
    if ok and tonumber(value) ~= nil then return math.max(0, math.min(1, value / 10)) end
    return 1
end

local function isMine(_box)
    for _, player in ipairs(localListeners()) do
        if COOPBoombox.playerKey(player) == _box.holder then return player end
    end
    return nil
end

-- One line per boombox this client can hear. `time` is the local clock the positions are
-- for; the speaker counts on from it, on the same clock.
local function writeOut(_t)
    local lines = { "coop-boombox 1", "time " .. string.format("%.0f", _t) }
    local heard = false
    if COOPBoombox.isEnabled() then
        local listeners = localListeners()
        local master = gameVolume()
        local frozen = isGamePaused()
        for id, box in pairs(COOPBoomboxUI.boxes) do
            local holder = COOPBoombox.playerFor(box.holder)
            local loud = 0
            if holder ~= nil then
                for _, listener in ipairs(listeners) do
                    loud = math.max(loud, COOPBoombox.loudness(box, holder, listener))
                end
            end
            loud = loud * master
            if loud > 0.005 then
                local paused = (box.paused or frozen) and 1 or 0
                table.insert(lines, string.format("box %d|%.3f|%.2f|%d|%s", id, loud,
                        COOPBoombox.position(box, _t), paused, box.url))
                box.audible = true
                heard = true
            else
                box.audible = false
            end
        end
    end
    table.insert(lines, "end")
    heardLast = heard

    local writer = getFileWriter(COOPBoombox.OUT_FILE, true, false)
    if writer == nil then return end
    writer:write(table.concat(lines, "\n") .. "\n")
    writer:close()
end

-- alive <ms>
-- meta <id>|<duration or 0>|<url>|<title>
-- error <id>|<url>|<text>
local function readIn()
    local reader = getFileReader(COOPBoombox.IN_FILE, false)
    if reader == nil then return end
    local alive, meta, errors = 0, {}, {}
    while true do
        local line = reader:readLine()
        if line == nil then break end
        local kind, rest = line:match("^(%a+) (.*)$")
        if kind == "alive" then
            alive = tonumber(rest) or 0
        elseif kind == "meta" then
            local id, duration, url, title = rest:match("^(%d+)|([%d%.]+)|([^|]*)|(.*)$")
            if id ~= nil then
                meta[tonumber(id)] = { duration = tonumber(duration), url = url, title = title }
            end
        elseif kind == "error" then
            local id, url, text = rest:match("^(%d+)|([^|]*)|(.*)$")
            if id ~= nil then errors[tonumber(id)] = { url = url, text = text } end
        end
    end
    reader:close()
    speaker.alive, speaker.meta, speaker.errors = alive, meta, errors
end

-- The title and length the speaker found, for a boombox in our own hands, go to the
-- server so everyone sees them - again only if the speaker learns more.
local function passOnMeta()
    for id, info in pairs(speaker.meta) do
        local box = COOPBoomboxUI.boxes[id]
        local sig = tostring(info.url) .. "|" .. tostring(info.duration) .. "|" .. tostring(info.title)
        if box ~= nil and box.url == info.url and metaSent[id] ~= sig then
            local player = isMine(box)
            if player ~= nil and COOPBoombox.holds(player, id) then
                metaSent[id] = sig
                local duration = info.duration
                if duration ~= nil and duration <= 0 then duration = nil end
                COOPBoomboxUI.send(player, COOPBoombox.CMD_META, {
                    item = id, url = info.url, title = info.title, duration = duration,
                })
            end
        end
    end
end

-- Somebody else's boombox we can hear started a track: say what it is, once.
local function announce()
    for id, box in pairs(COOPBoomboxUI.boxes) do
        if box.audible and box.title ~= nil and announced[id] ~= box.url and isMine(box) == nil then
            announced[id] = box.url
            COOP.sayInChat(getText("UI_COOP_Boombox_Hearing", tostring(box.name), box.title), 0.75, 0.85, 1.0)
        end
    end
end

local function onTick()
    local t = now()

    if not synced and t >= nextSync then
        nextSync = t + SYNC_RETRY_MS
        local player = getPlayer()
        if player ~= nil then COOPBoomboxUI.send(player, COOPBoombox.CMD_SYNC, {}) end
    end

    if t - lastWrite >= (heardLast and WRITE_MS or HEARTBEAT_MS) then
        lastWrite = t
        pcall(writeOut, t)
    end

    if t - lastRead >= READ_MS then
        lastRead = t
        pcall(readIn)
        if COOPBoombox.isEnabled() then
            pcall(passOnMeta)
            pcall(announce)
        end
    end
end

Events.OnTick.Add(onTick)

-- ---------------------------------------------------------------------------
-- the window
-- ---------------------------------------------------------------------------

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local UI_BORDER_SPACING = 10
local BUTTON_HGT = FONT_HGT_SMALL + 6

local COLOR_GOOD = { r = 0.45, g = 0.85, b = 0.45 }
local COLOR_BAD = { r = 0.95, g = 0.45, b = 0.40 }
local COLOR_DIM = { r = 0.62, g = 0.62, b = 0.62 }

COOPBoomboxWindow = ISCollapsableWindow:derive("COOPBoomboxWindow")
COOPBoomboxWindow.instance = nil

function COOPBoomboxWindow:addButton(_x, _y, _text, _onclick)
    local width = math.max(80, getTextManager():MeasureStringX(UIFont.Small, _text) + 20)
    local btn = ISButton:new(_x, _y, width, BUTTON_HGT, _text, self, _onclick)
    btn:initialise()
    btn:instantiate()
    self:addChild(btn)
    return btn
end

function COOPBoomboxWindow:createChildren()
    ISCollapsableWindow.createChildren(self)

    local x = UI_BORDER_SPACING
    local y = self:titleBarHeight() + UI_BORDER_SPACING
    local inner = self.width - x * 2

    self.statusY = y
    y = y + FONT_HGT_SMALL + UI_BORDER_SPACING

    self.linkLabelY = y
    y = y + FONT_HGT_SMALL + 2
    self.link = ISTextEntryBox:new(self.lastUrl or "", x, y, inner, BUTTON_HGT)
    self.link.font = UIFont.Small
    self.link:initialise()
    self.link:instantiate()
    self.link:setMaxTextLength(COOPBoombox.URL_MAX)
    self.link.onCommandEntered = function() self:onPlay() end
    self:addChild(self.link)
    y = y + BUTTON_HGT + 6

    self.btnPlay = self:addButton(x, y, getText("UI_COOP_Boombox_Play"), COOPBoomboxWindow.onPlay)
    self.btnPause = self:addButton(self.btnPlay:getRight() + 4, y, getText("UI_COOP_Boombox_Pause"), COOPBoomboxWindow.onPause)
    self.btnStop = self:addButton(self.btnPause:getRight() + 4, y, getText("UI_COOP_Boombox_Stop"), COOPBoomboxWindow.onStop)
    self.btnStop:enableCancelColor()
    y = y + BUTTON_HGT + UI_BORDER_SPACING

    self.nowY = y
    y = y + FONT_HGT_MEDIUM + 2 + FONT_HGT_SMALL + UI_BORDER_SPACING

    self.volumeLabelY = y
    y = y + FONT_HGT_SMALL + 2
    self.volumeBar = ISVolumeBar:new(x, y, inner, BUTTON_HGT, COOPBoomboxWindow.onVolumeChange, self)
    self.volumeBar:initialise()
    self.volumeBar:setVolumeSteps(COOPBoombox.VOLUME_STEPS)
    self.volumeBar:setVolume(math.floor(self:volume() * COOPBoombox.VOLUME_STEPS + 0.5))
    self:addChild(self.volumeBar)
    y = y + BUTTON_HGT + UI_BORDER_SPACING

    self.hintY = y
    self:setHeight(y + FONT_HGT_SMALL * 2 + UI_BORDER_SPACING)
end

function COOPBoomboxWindow:box()
    return COOPBoomboxUI.boxes[self.itemId]
end

function COOPBoomboxWindow:held()
    return COOPBoombox.holds(self.player, self.itemId)
end

-- The volume of a boombox that is not playing is kept with the item on this client, so
-- it starts at the level it was left at.
function COOPBoomboxWindow:volume()
    local box = self:box()
    if box ~= nil then return COOPBoombox.clampVolume(box.volume) end
    local saved = self.item and self.item:getModData().coopBoomboxVolume
    if saved ~= nil then return COOPBoombox.clampVolume(saved) end
    return COOPBoombox.DEFAULT_VOLUME
end

function COOPBoomboxWindow:onPlay()
    local url = COOPBoombox.cleanUrl(self.link:getText())
    if url == nil then
        self.message = getText("UI_COOP_Boombox_BadLink")
        return
    end
    if not self:held() then
        self.message = getText("UI_COOP_Boombox_NotHeld")
        return
    end
    self.message = nil
    self.link:setText(url)
    if self.item ~= nil then self.item:getModData().coopBoomboxUrl = url end
    COOPBoomboxUI.send(self.player, COOPBoombox.CMD_PLAY, { item = self.itemId, url = url, volume = self:volume() })
end

function COOPBoomboxWindow:onPause()
    local box = self:box()
    if box == nil or not self:held() then return end
    COOPBoomboxUI.send(self.player, COOPBoombox.CMD_PAUSE, { item = self.itemId, paused = not box.paused })
end

function COOPBoomboxWindow:onStop()
    if self:box() == nil or not self:held() then return end
    COOPBoomboxUI.send(self.player, COOPBoombox.CMD_STOP, { item = self.itemId })
end

function COOPBoomboxWindow:onVolumeChange(_steps)
    local volume = COOPBoombox.clampVolume(_steps / COOPBoombox.VOLUME_STEPS)
    self.volumeBar:setVolume(_steps)
    if self.item ~= nil then self.item:getModData().coopBoomboxVolume = volume end
    if self:box() ~= nil and self:held() then
        COOPBoomboxUI.send(self.player, COOPBoombox.CMD_VOLUME, { item = self.itemId, volume = volume })
    end
end

function COOPBoomboxWindow:update()
    ISCollapsableWindow.update(self)

    -- the boombox left the inventory altogether: nothing left to control
    if self.item == nil or not self.player:getInventory():containsRecursive(self.item) then
        self:close()
        return
    end

    local box, held = self:box(), self:held()
    self.btnPlay:setEnable(held)
    self.btnPause:setEnable(held and box ~= nil)
    self.btnStop:setEnable(held and box ~= nil)
    self.btnPause:setTitle(getText((box and box.paused) and "UI_COOP_Boombox_Resume" or "UI_COOP_Boombox_Pause"))
    self.volumeBar:setEnableControls(held)
    if box ~= nil and not self.volumeBar:isDragging() and self.volumeBar:getHoverVolume() < 1 then
        self.volumeBar:setVolume(math.floor(COOPBoombox.clampVolume(box.volume) * COOPBoombox.VOLUME_STEPS + 0.5))
    end
end

function COOPBoomboxWindow:prerender()
    ISCollapsableWindow.prerender(self)
    local x = UI_BORDER_SPACING
    local inner = self.width - x * 2

    if COOPBoomboxUI.speakerRunning() then
        self:drawText(getText("UI_COOP_Boombox_SpeakerOn"), x, self.statusY, COLOR_GOOD.r, COLOR_GOOD.g, COLOR_GOOD.b, 1, UIFont.Small)
    else
        self:drawText(getText("UI_COOP_Boombox_SpeakerOff"), x, self.statusY, COLOR_BAD.r, COLOR_BAD.g, COLOR_BAD.b, 1, UIFont.Small)
    end

    self:drawText(getText("UI_COOP_Boombox_Link"), x, self.linkLabelY, COLOR_DIM.r, COLOR_DIM.g, COLOR_DIM.b, 1, UIFont.Small)

    local box = self:box()
    local title, sub
    if box == nil then
        title = getText("UI_COOP_Boombox_Silent")
        sub = ""
    else
        title = box.title or box.url
        local pos = COOPBoombox.position(box, now())
        if box.duration ~= nil then pos = math.min(pos, box.duration) end
        sub = COOPBoombox.formatTime(pos)
        if box.duration ~= nil then sub = sub .. " / " .. COOPBoombox.formatTime(box.duration) end
        if box.paused then sub = sub .. "   " .. getText("UI_COOP_Boombox_Paused") end
    end
    title = self:fit(title, UIFont.Medium, inner)
    self:drawText(title, x, self.nowY, 1, 1, 1, 1, UIFont.Medium)
    self:drawText(sub, x, self.nowY + FONT_HGT_MEDIUM + 2, COLOR_DIM.r, COLOR_DIM.g, COLOR_DIM.b, 1, UIFont.Small)

    local volumeText = getText("UI_COOP_Boombox_Volume", tostring(math.floor(self:volume() * 100 + 0.5)) .. "%")
    self:drawText(volumeText, x, self.volumeLabelY, COLOR_DIM.r, COLOR_DIM.g, COLOR_DIM.b, 1, UIFont.Small)

    local hint, color = self.message, COLOR_BAD
    if hint == nil and box ~= nil then
        hint = COOPBoomboxUI.speakerError(self.itemId, box.url)
        if hint ~= nil then hint = getText("UI_COOP_Boombox_SpeakerFailed", hint) end
    end
    if hint == nil and not self:held() then
        hint, color = getText("UI_COOP_Boombox_HoldIt"), COLOR_DIM
    end
    if hint ~= nil then
        self:drawText(self:fit(hint, UIFont.Small, inner), x, self.hintY, color.r, color.g, color.b, 1, UIFont.Small)
    end
end

function COOPBoomboxWindow:fit(_text, _font, _width)
    local text = tostring(_text or "")
    local tm = getTextManager()
    if tm:MeasureStringX(_font, text) <= _width then return text end
    while #text > 1 and tm:MeasureStringX(_font, text .. "...") > _width do
        text = text:sub(1, #text - 1)
    end
    return text .. "..."
end

-- ESC closes, and is swallowed so it does not also open the main menu.
function COOPBoomboxWindow:isKeyConsumed(_key)
    return _key == Keyboard.KEY_ESCAPE
end

function COOPBoomboxWindow:onKeyRelease(_key)
    if _key == Keyboard.KEY_ESCAPE and self:getIsVisible() then
        self:close()
    end
end

function COOPBoomboxWindow:close()
    self:setVisible(false)
    self:removeFromUIManager()
    if COOPBoomboxWindow.instance == self then COOPBoomboxWindow.instance = nil end
end

function COOPBoomboxWindow:new(_x, _y, _width, _height, _player, _item)
    local o = ISCollapsableWindow:new(_x, _y, _width, _height)
    setmetatable(o, self)
    self.__index = self
    o.title = getText("UI_COOP_Boombox_Title")
    o.player = _player
    o.item = _item
    o.itemId = _item:getID()
    local box = COOPBoomboxUI.boxes[o.itemId]
    o.lastUrl = (box and box.url) or _item:getModData().coopBoomboxUrl or ""
    o:setResizable(false)
    return o
end

Events.OnGameStart.Add(function()
    local window = COOPBoomboxWindow.instance
    if window ~= nil then
        window:removeFromUIManager()
        COOPBoomboxWindow.instance = nil
    end
end)

function COOPBoomboxWindow.open(_player, _item)
    if COOPBoomboxWindow.instance ~= nil then COOPBoomboxWindow.instance:close() end
    local width = 440
    local window = COOPBoomboxWindow:new((getCore():getScreenWidth() - width) / 2,
            getCore():getScreenHeight() / 2 - 150, width, 300, _player, _item)
    window:initialise()
    window:instantiate()
    window:setVisible(true)
    window:addToUIManager()
    COOPBoomboxWindow.instance = window
end

-- ---------------------------------------------------------------------------
-- the inventory context menu
-- ---------------------------------------------------------------------------

local function onFillInventoryObjectContextMenu(_playerNum, _context, _items)
    if not COOPBoombox.isEnabled() then return end
    local player = getSpecificPlayer(_playerNum)
    if player == nil then return end

    local boombox = nil
    for _, entry in ipairs(_items) do
        local item = entry
        if type(entry) == "table" and entry.items ~= nil then item = entry.items[1] end
        if COOPBoombox.isBoombox(item) then boombox = item; break end
    end
    if boombox == nil or not player:getInventory():containsRecursive(boombox) then return end

    _context:addOption(getText("ContextMenu_COOP_Boombox_Open"), player, COOPBoomboxWindow.open, boombox)
end

Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)
