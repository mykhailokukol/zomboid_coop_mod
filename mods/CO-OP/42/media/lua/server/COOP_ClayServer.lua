--
-- CO-OP - authority over digging clay.
--
-- Runs on the dedicated/hosted server, and also in single player where there is no
-- server process and the client calls these functions directly.
--
-- Everything that matters happens here rather than in the action: the per-square
-- cooldown is shared state, so two players must not be able to dig the same bank twice
-- in the same week, and the clay itself is an item somebody could otherwise ask for
-- twice. The client's dig action only plays the animation and then says "I dug here".
--
-- The XP is awarded here too, and that is not a stylistic choice. The global addXp
-- forwards to GameServer.addXp when it runs on the server, does the plain
-- getXp():AddXP() when there is no network at all, and - checked in the bytecode of
-- LuaManager$GlobalObject.addXp - falls through and does *nothing whatsoever* when
-- GameClient.client is set. Awarding from the digging client would have been silently
-- lost in multiplayer.
--

if isClient() then return end

require "COOP_Clay"

COOPClayServer = {}

local writeBudget = {}

-- Same shape as the books and to-do lists: a burst is fine, a flood is not.
local function rateLimited(_playerObj)
    local key = COOP.playerName(_playerObj)
    local now = getTimestampMs()
    local budget = writeBudget[key]

    if budget == nil or now - budget.start > COOPClay.WRITE_WINDOW_MS then
        writeBudget[key] = { start = now, count = 1 }
        return false
    end

    budget.count = budget.count + 1
    return budget.count > COOPClay.WRITE_LIMIT
end

local function ensureData()
    local data = ModData.getOrCreate(COOPClay.MODDATA_KEY)
    if data.version == nil then data.version = COOPClay.SCHEMA end
    if data.entries == nil then data.entries = {} end
    return data
end

-- Drops every square whose cooldown has run out. The table is only ever read to answer
-- "can this be dug", so an expired entry is indistinguishable from no entry at all -
-- which is what keeps this from growing with the age of the save.
local function prune(_data)
    local removed = {}
    for key, _ in pairs(_data.entries) do
        if COOPClay.cooldownLeft(_data.entries, key) <= 0 then
            table.insert(removed, key)
        end
    end
    for _, key in ipairs(removed) do
        _data.entries[key] = nil
    end
    return removed
end

function COOPClayServer.getEntries()
    local data = ensureData()
    prune(data)
    return data.entries
end

local function broadcast(_key, _day)
    if not isServer() then return end
    sendServerCommand(COOPClay.MODULE, COOPClay.CMD_DELTA, {
        key = _key,
        day = _day,
        removed = _day == nil,
    })
end

-- Tells the digger how it went. Only ever sent to the one player who asked, because it
-- is feedback on their own action and nobody else's business.
local function reply(_playerObj, _amount, _reason)
    if not isServer() then return end
    sendServerCommand(_playerObj, COOPClay.MODULE, COOPClay.CMD_RESULT, {
        amount = _amount,
        reason = _reason,
    })
end

-- ---------------------------------------------------------------------------
-- placing the clay
-- ---------------------------------------------------------------------------

-- Into the digger's hands, or wherever their output picker says. The item is added to
-- the inventory first and moved out afterwards, exactly the way the vehicle-part hooks
-- in COOP_Output work, so the fallback when the destination is full or out of reach is
-- simply "it stayed in the inventory" and a lump of clay is never lost.
--
-- The category is smithing, which is this mod's forge-and-kiln bucket and the one that
-- already covers Pottery (see the output feature's CATEGORY_RULES): a player who sends
-- that kind of output to a crate gets their clay there too.
--
-- `_action` is the dig action itself and is only ever non-nil in single player, where
-- both halves share one Lua state: resolveDestination prefers the set stamped on the
-- action and falls back to the one the client pushed over the command channel, which is
-- the multiplayer path. COOP_ClayUI stamps and sends at the moment the action is created
-- so the "nearby container" coordinates are fresh.
local function giveClay(_character, _count, _action)
    local inventory = _character:getInventory()
    if inventory == nil then return 0 end

    local destination = nil
    if COOPOutput ~= nil then
        pcall(function()
            destination = COOPOutput.resolveDestination(_action, _character, COOPOutput.SMITHING)
        end)
    end

    local given = 0
    for _ = 1, _count do
        local item = inventory:AddItem(COOPClay.ITEM)
        if item == nil then break end

        local moved = false
        if COOPOutput ~= nil and destination ~= nil then
            local ok, result = pcall(function()
                return COOPOutput.relocateFromInventory(destination, _character, item)
            end)
            moved = ok and result == true
        end

        if not moved then
            -- the sync call vanilla's own wormCheck makes after AddItem
            sendAddItemToContainer(inventory, item)
        end

        given = given + 1
    end

    return given
end

-- ---------------------------------------------------------------------------
-- the dig
-- ---------------------------------------------------------------------------

-- Answers the number of lumps handed over, or 0 with a reason. Everything the client
-- claimed is re-checked here against the server's own copy of the map and of the
-- cooldown table; the client is only trusted for which square it meant.
function COOPClayServer.dig(_playerObj, _args, _action)
    if not COOPClay.isEnabled() then return 0, "off" end
    if _playerObj == nil or _args == nil then return 0, "off" end
    if rateLimited(_playerObj) then return 0, "rate" end

    local x = tonumber(_args.x)
    local y = tonumber(_args.y)
    local z = tonumber(_args.z)
    if x == nil or y == nil or z == nil then return 0, "where" end

    -- Distance is checked here for the same reason the ping cooldown is: a client must not be able to work a riverbank on the other side of the
    -- map. One tile of slack over the client's own reach covers a player who took a step
    -- while the action finished.
    if math.abs(_playerObj:getX() - x) > COOPClay.REACH + 1
            or math.abs(_playerObj:getY() - y) > COOPClay.REACH + 1 then
        return 0, "far"
    end

    local cell = getCell()
    local square = cell ~= nil and cell:getGridSquare(x, y, z) or nil
    if square == nil then return 0, "where" end
    if not COOPClay.canDigSquare(square) then return 0, "where" end

    -- The shovel is checked on this side too: the action needs one to start, but the
    -- item could have been dropped, broken or handed over in the meantime.
    if COOPClay.findShovel(_playerObj) == nil then return 0, "shovel" end

    local data = ensureData()
    prune(data)

    local key = COOPClay.squareKey(x, y, z)
    if COOPClay.cooldownLeft(data.entries, key) > 0 then
        return 0, "cooldown"
    end

    local amount = COOPClay.rollAmount(COOPClay.perkLevel(_playerObj))
    local given = giveClay(_playerObj, amount, _action)
    if given <= 0 then return 0, "full" end

    -- Only now is the square marked: a dig that produced nothing has not used it up.
    local count = 0
    for _ in pairs(data.entries) do count = count + 1 end
    if count < COOPClay.MAX_ENTRIES then
        local day = COOPClay.nowDays()
        data.entries[key] = day
        broadcast(key, day)
    else
        COOP.log("clay cooldown table is full, not recording " .. key)
    end

    -- The perk is Perks.Pottery; addXp is a no-op on a client, so this only works
    -- because it is being called on the authoritative side.
    local perk = COOPClay.perk()
    local xp = COOPClay.digXp()
    if perk ~= nil and xp > 0 then
        pcall(function() addXp(_playerObj, perk, xp) end)
    end

    if COOPClay.debug then
        COOP.log(COOP.playerName(_playerObj) .. " dug " .. given .. " clay at " .. key)
    end

    return given
end

-- ---------------------------------------------------------------------------
-- commands
-- ---------------------------------------------------------------------------

local function onClientCommand(_module, _command, _playerObj, _args)
    if _module ~= COOPClay.MODULE then return end
    if not COOPClay.isEnabled() then return end

    if _command == COOPClay.CMD_DIG then
        local amount, reason = COOPClayServer.dig(_playerObj, _args)
        reply(_playerObj, amount, reason)
    elseif _command == COOPClay.CMD_SYNC_REQUEST then
        if not isServer() then return end
        sendServerCommand(_playerObj, COOPClay.MODULE, COOPClay.CMD_SYNC, {
            entries = COOPClayServer.getEntries(),
            version = COOPClay.SCHEMA,
        })
    end
end

Events.OnClientCommand.Add(onClientCommand)
