--
-- CO-OP / Books at home - hotkey.
--

if isServer() then return end

require "BAH_Common"

local BIND_NAME = "Toggle Books At Home"
local registered = false

local function initBinds()
    table.insert(keyBinding, { value = "[Books At Home]" })
    table.insert(keyBinding, { value = BIND_NAME, key = Keyboard.KEY_K })
end

local function onKeyPressed(_key)
    if isGamePaused() then return end
    if getPlayer() == nil then return end
    if getCore():isKey(BIND_NAME, _key) then
        BooksAtHomeWindow.toggle()
    end
end

local function onGameStart()
    if registered then return end
    registered = true
    Events.OnKeyPressed.Add(onKeyPressed)
end

Events.OnGameBoot.Add(initBinds)
Events.OnGameStart.Add(onGameStart)
