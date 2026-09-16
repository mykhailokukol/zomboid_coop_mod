--
-- CO-OP - shared helpers for the mod as a whole.
--
-- Feature modules keep their own prefixes (BAH_* for the "books at home" list);
-- anything used by more than one feature belongs here.
--

COOP = COOP or {}

function COOP.log(_msg)
    print("[CO-OP] " .. tostring(_msg))
end

-- The name to credit an action to: the multiplayer username, else the character's
-- forename. "?" when neither can be read.
function COOP.playerName(_playerObj)
    if _playerObj == nil then return "?" end

    local okUser, user = pcall(function() return _playerObj:getUsername() end)
    if okUser and user and user ~= "" then return tostring(user) end

    local okDesc, forename = pcall(function() return _playerObj:getDescriptor():getForename() end)
    if okDesc and forename and forename ~= "" then return tostring(forename) end

    return "?"
end

-- In-game calendar stamp, e.g. "12/07/1993 14:20". Safe to call from either side.
function COOP.gameDateString()
    local ok, stamp = pcall(function()
        local gt = getGameTime()
        return string.format("%02d/%02d/%d %02d:%02d",
                gt:getDay() + 1, gt:getMonth() + 1, gt:getYear(),
                gt:getHour(), gt:getMinutes())
    end)
    if ok and stamp then return stamp end
    return "?"
end

-- Monotonic in-game hours, for sorting things into the order they happened.
function COOP.worldAgeHours()
    local ok, hours = pcall(function() return getGameTime():getWorldAgeHours() end)
    if ok and hours then return hours end
    return 0
end

-- ---------------------------------------------------------------------------
-- chat
-- ---------------------------------------------------------------------------

-- Writes one line into the player's own chat window. Local to this client: nothing is
-- sent anywhere, the caller has already received whatever it is announcing.
--
-- There is no Lua-side way to build a real ChatMessage - its constructor wants a
-- ChatBase, and ChatManager, which owns showServerChatMessage, is not in
-- LuaManager$Exposer's list at all. But ISChat only ever calls getTextWithPrefix() and
-- getAuthor() on a message, and its one other consumer (updateChatPrefixSettings, when
-- the timestamp setting changes) calls getTextWithPrefix() again - so a small Lua
-- stand-in is enough.
--
-- _r/_g/_b are optional and colour the whole line.
function COOP.sayInChat(_text, _r, _g, _b)
    if _text == nil then return false end

    local ok, sent = pcall(function()
        if ISChat == nil then return false end

        local chat = ISChat.instance
        if chat == nil or chat.tabs == nil then return false end

        -- The main tab has to exist: addLineInChat drops the message otherwise, and on a
        -- server with the general channel off there is nowhere to put it.
        local hasMainTab = false
        for _, tab in ipairs(chat.tabs) do
            if tab ~= nil and tab.tabID == 1 then hasMainTab = true; break end
        end
        if not hasMainTab then return false end

        local text = tostring(_text)
        if _r ~= nil and _g ~= nil and _b ~= nil then
            text = string.format("<RGB:%.2f,%.2f,%.2f> ", _r, _g, _b) .. text
        end

        local message = {}
        function message:getTextWithPrefix() return text end
        function message:getAuthor() return nil end
        function message:setText(_newText) end

        ISChat.addLineInChat(message, 1)
        return true
    end)

    return ok and sent == true
end

-- ---------------------------------------------------------------------------
-- sandbox options
--
-- Everything tunable lives in media/sandbox-options.txt under the COOP namespace, so a
-- server admin can change it without touching the mod. SandboxVars is not populated
-- until the world loads and, on a multiplayer client, it arrives from the server - so
-- these are read at the moment they are needed, never cached at file load, and every
-- one falls back to the value the mod would have used before options existed.
-- ---------------------------------------------------------------------------

COOP.OPTIONS = "COOP"

-- feature switches
COOP.F_BOOKS = "BooksAtHome"
COOP.F_MAPSHARE = "MapShare"
COOP.F_OUTPUT = "ItemOutput"
COOP.F_ORGANIZATION = "Organization"
COOP.F_PINGS = "Pings"
COOP.F_TODO = "Todo"
COOP.F_HOTBAR = "HotbarStatus"
COOP.F_MIXER = "ConcreteMixer"
COOP.F_PUSH = "PushVehicle"
COOP.F_CLAY = "ClayDigging"

function COOP.option(_name, _default)
    local ok, value = pcall(function()
        local vars = SandboxVars and SandboxVars[COOP.OPTIONS]
        if vars == nil then return nil end
        return vars[_name]
    end)
    if ok and value ~= nil then return value end
    return _default
end

function COOP.numberOption(_name, _default, _min, _max)
    local value = tonumber(COOP.option(_name, _default))
    if value == nil or value ~= value then return _default end
    if _min ~= nil and value < _min then return _min end
    if _max ~= nil and value > _max then return _max end
    return value
end

-- Features are on unless the server turned them off.
function COOP.featureEnabled(_name)
    return COOP.option(_name, true) ~= false
end
