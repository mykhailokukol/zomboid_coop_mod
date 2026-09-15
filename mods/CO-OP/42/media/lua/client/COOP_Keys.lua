--
-- CO-OP - the mod's key bindings.
--
-- Registered in one place so the options screen shows a single [CO-OP] section.
-- "Books at home" keeps its own section, because that feature's wording stays separate.
--
-- Mouse buttons are ordinary binding codes: Mouse.BTN_OFFSET (10000) plus the button
-- index, exactly how vanilla binds Attack/Click to Mouse.LMB. That is why Ping can
-- default to the middle mouse button and still be rebindable to a key.
--

if isServer() then return end

require "COOP_Common"

COOPKeys = COOPKeys or {}

COOPKeys.SECTION = "[CO-OP]"
COOPKeys.PING = "Ping"
COOPKeys.TODO = "Toggle to-do list"

local registered = false

-- A mod file can be run more than once in a Lua state, and a second pass would add a
-- second copy of every binding to the options screen. Ask the table instead of trusting
-- a local flag, which a re-run would reset along with everything else.
local function alreadyListed(_value)
    for _, bind in ipairs(keyBinding) do
        if bind ~= nil and bind.value == _value then return true end
    end
    return false
end

local function bind(_value, _key)
    if alreadyListed(_value) then return end
    table.insert(keyBinding, { value = _value, key = _key })
end

local function initBinds()
    bind(COOPKeys.SECTION, nil)
    bind(COOPKeys.PING, Mouse.MMB)
    -- vanilla keyBinding.lua leaves exactly one letter free (K), and "Books at home"
    -- already has it, so the to-do list starts on a bracket. Rebindable either way.
    bind(COOPKeys.TODO, Keyboard.KEY_LBRACKET)
end

local function onKeyPressed(_key)
    if isGamePaused() then return end
    if getPlayer() == nil then return end

    if getCore():isKey(COOPKeys.TODO, _key) then
        COOPTodoWindow.toggle()
    end
end

local function onGameStart()
    if registered then return end
    registered = true
    Events.OnKeyPressed.Add(onKeyPressed)
end

Events.OnGameBoot.Add(initBinds)
Events.OnGameStart.Add(onGameStart)
