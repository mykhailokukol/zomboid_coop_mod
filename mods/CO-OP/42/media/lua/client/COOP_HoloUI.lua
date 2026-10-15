--
-- CO-OP - holograms on the client: the button, the cursor, the drawing and the menu.
--
-- The list itself is the server's (COOP_HoloServer.lua). Here it is a cache fed by the
-- server, or the server's own table in single player, exactly as for the to-do list.
--
-- Drawing: B42 renders the world through FBORenderCell, which never fires
-- OnPostFloorLayerDraw. RenderOpaqueObjectsInWorld does fire every frame, inside the
-- world render - the fishing bobber and the 3D item cursor draw from it - and
-- IsoSprite:RenderGhostTileColor is what the build cursor itself draws with.
--
-- The cursor is ISBuildIsoEntity with three changes: materials, skills and tools are
-- not asked for, it draws blue, and placing it sends a hologram to the server instead
-- of starting a build. Where an object may stand is still vanilla's (and our
-- COOP_BuildIsValid's) rule. ISBuildIsoEntity lives under lua/server, which the client
-- loads after lua/client, so the class is made on first use.
--

if isServer() then return end

require "COOP_Holo"

COOPHoloUI = COOPHoloUI or {}

-- ---------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------

local cache = {}
local synced = false
local nextRequestMs = 0

local REQUEST_RETRY_MS = 10000

function COOPHoloUI.getEntries()
    if isClient() then return cache end
    if COOPHoloServer then return COOPHoloServer.getEntries() end
    return {}
end

local function request(_command, _args)
    if isClient() then
        local player = getPlayer()
        if player == nil then return end
        sendClientCommand(player, COOPHolo.MODULE, _command, _args)
        return
    end

    -- Single player: no round trip, call the authority directly.
    if COOPHoloServer == nil then
        COOP.log("hologram server module missing, cannot " .. tostring(_command))
        return
    end
    local player = getPlayer()
    if _command == COOPHolo.CMD_ADD then
        COOPHoloServer.add(player, _args.name, _args.nSprite, _args.x, _args.y, _args.z)
    elseif _command == COOPHolo.CMD_REMOVE then
        COOPHoloServer.remove(player, _args.id)
    end
end

function COOPHoloUI.add(_name, _nSprite, _x, _y, _z)
    request(COOPHolo.CMD_ADD, { name = _name, nSprite = _nSprite, x = _x, y = _y, z = _z })
end

function COOPHoloUI.remove(_id)
    request(COOPHolo.CMD_REMOVE, { id = _id })
end

local function exists(_name, _nSprite, _x, _y, _z)
    for _, entry in pairs(COOPHoloUI.getEntries()) do
        if entry.name == _name and entry.nSprite == _nSprite and entry.x == _x and entry.y == _y and entry.z == _z then
            return true
        end
    end
    return false
end

local function onServerCommand(_module, _command, _args)
    if _module ~= COOPHolo.MODULE then return end

    if _command == COOPHolo.CMD_SYNC then
        cache = (_args and _args.entries) or {}
        synced = true
        COOP.log("received the holograms from the server")
    elseif _command == COOPHolo.CMD_DELTA then
        if _args == nil or _args.id == nil then return end
        if _args.removed or _args.entry == nil then
            cache[_args.id] = nil
        else
            cache[_args.id] = _args.entry
        end
    end
end

-- Keep asking until the server answers: the first request can land before the player
-- is fully connected.
local function onTick()
    if not isClient() or synced then return end
    if getPlayer() == nil then return end
    if getTimestampMs() < nextRequestMs then return end
    nextRequestMs = getTimestampMs() + REQUEST_RETRY_MS
    sendClientCommand(getPlayer(), COOPHolo.MODULE, COOPHolo.CMD_SYNC_REQUEST, {})
end

-- ---------------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------------

local RANGE = 60  -- squares from the player a hologram is still drawn

-- Own sprite objects per name, as ISBuildIsoEntity:cacheSprites keeps them.
local sprites = {}

local function spriteFor(_name)
    local sprite = sprites[_name]
    if sprite == nil then
        sprite = IsoSprite.new()
        sprite:LoadSingleTexture(_name)
        sprites[_name] = sprite
    end
    return sprite
end

-- A lamp on a table is drawn on the table top, as the cursor draws it. Worked out once
-- per square, the first time the square is loaded. Kept beside the tile, not on it: in
-- single player the tile is the server's, and would carry the number into the save.
local offsets = setmetatable({}, { __mode = "k" })

local function offsetFor(_tile)
    if offsets[_tile] ~= nil then return offsets[_tile] end
    local square = getCell():getGridSquare(_tile.x, _tile.y, _tile.z)
    if square == nil then return 0 end
    local off = 0
    local shared = getSprite(_tile.s)
    if shared ~= nil and shared:getProperties():has("IsStackable") then
        local ok, height = pcall(function()
            return ISMoveableSpriteProps.new(shared):getTotalTableHeight(square)
        end)
        if ok and height then off = height * Core.getTileScale() end
    end
    offsets[_tile] = off
    return off
end

local function render(_playerIndex)
    if not COOPHolo.isEnabled() then return end
    local player = getSpecificPlayer(_playerIndex)
    if player == nil then return end

    local px, py = player:getX(), player:getY()
    local pz = math.floor(player:getZ())
    for _, entry in pairs(COOPHoloUI.getEntries()) do
        if entry.z <= pz and math.abs(entry.x - px) < RANGE and math.abs(entry.y - py) < RANGE then
            for _, tile in ipairs(entry.tiles) do
                if tile.z <= pz then
                    spriteFor(tile.s):RenderGhostTileColor(tile.x, tile.y, tile.z, 0, offsetFor(tile),
                        COOPHolo.R, COOPHolo.G, COOPHolo.B, COOPHolo.A)
                end
            end
        end
    end
end

local function onRenderOpaqueObjectsInWorld(_playerIndex)
    local ok, err = pcall(render, _playerIndex)
    if not ok then COOP.log("hologram render failed: " .. tostring(err)) end
end

-- ---------------------------------------------------------------------------
-- the cursor
-- ---------------------------------------------------------------------------

local Cursor = nil

local function cursorClass()
    if Cursor ~= nil or ISBuildIsoEntity == nil then return Cursor end
    Cursor = ISBuildIsoEntity:derive("COOPHoloCursor")

    -- Nothing is used, so nothing is needed: no materials, no hammer.
    function Cursor:haveMaterial(_square)
        return true
    end

    function Cursor:isValid(_square)
        if not ISBuildIsoEntity.isValid(self, _square) then return false end
        return not exists(self.name, self.nSprite, _square:getX(), _square:getY(), _square:getZ())
    end

    -- ISBuildIsoEntity:render, in blue.
    function Cursor:render(x, y, z, square)
        self:ensureSquaresExist(x, y, z)
        local valid = self:isValid(square)
        self:renderFloorGrid(x, y, z)

        local face = self:getFace()
        if not face then
            self.tileSprite:RenderGhostTileRed(x, y, z)
            return
        end
        for zz = 0, face:getzLayers() - 1 do
            for xx = 0, face:getWidth() - 1 do
                for yy = 0, face:getHeight() - 1 do
                    local tileInfo = face:getTileInfo(xx, yy, zz)
                    local name = tileInfo and tileInfo:getSpriteName()
                    local sprite = name and self.spriteCache[name]
                    if sprite then
                        local offsetY = 0
                        local shared = getSprite(name)
                        if shared and shared:getProperties():has("IsStackable") then
                            offsetY = ISMoveableSpriteProps.new(shared):getTotalTableHeight(square) * Core.getTileScale()
                        end
                        if valid then
                            sprite:RenderGhostTileColor(x + xx, y + yy, z + zz, 0, offsetY,
                                COOPHolo.R, COOPHolo.G, COOPHolo.B, 0.7)
                        else
                            sprite:RenderGhostTileColor(x + xx, y + yy, z + zz, 0, offsetY, 0.65, 0.2, 0.2, 0.6)
                        end
                    end
                end
            end
        end
    end

    -- Placing sends the plan; the cursor stays up for the next one (dragNilAfterPlace
    -- is off, so DoTileBuilding re-arms it). Escape or right-click puts it away.
    function Cursor:tryBuild(x, y, z)
        self:getFace()
        COOPHoloUI.add(self.name, self.nSprite, x, y, z)
    end

    function Cursor:walkTo(x, y, z)
        return true
    end

    return Cursor
end

function COOPHoloUI.startCursor(_player, _info)
    local class = cursorClass()
    if class == nil or _player == nil or _info == nil then return end
    local containers = ISInventoryPaneContextMenu.getContainers(_player)
    local cursor = class:new(_player, _info, 1, containers)
    cursor.dragNilAfterPlace = false
    cursor.blockAfterPlace = false
    getCell():setDrag(cursor, _player:getPlayerNum())
end

-- ---------------------------------------------------------------------------
-- "Build this": the real build, at the hologram's square and rotation
-- ---------------------------------------------------------------------------

-- ISEntityBuildMenu's own getTool, which is local there.
local function getTool(_inputScript, _inventory)
    if not _inputScript then return nil end
    local entryItems = _inputScript:getPossibleInputItems()
    for m = 0, entryItems:size() - 1 do
        local itemType = entryItems:get(m):getFullName()
        local result = _inventory:getAllTypeEvalRecurse(itemType, ISBuildIsoEntity.predicateMaterial)
        if result:size() > 0 then return result:get(0):getFullType() end
    end
    return nil
end

-- The vanilla build entity the right-click build menu makes (ISEntityBuildMenu
-- .onBuildEntity), turned to the hologram's rotation. Also says whether this player
-- could build it now.
local function realEntity(_player, _entry)
    local info = SpriteConfigManager.GetObjectInfo(_entry.name)
    if info == nil or info:getRecipe() == nil then return nil, false end

    local containers = ISInventoryPaneContextMenu.getContainers(_player)
    local entity = ISBuildIsoEntity:new(_player, info, _entry.nSprite, containers)
    entity.player = _player:getPlayerNum()

    local recipe = info:getRecipe():getCraftRecipe()
    local inventory = _player:getInventory()
    entity.equipBothHandItem = getTool(recipe:getToolBoth(), inventory)
    entity.firstItem = getTool(recipe:getToolRight(), inventory)
    entity.secondItem = getTool(recipe:getToolLeft(), inventory)

    local logic = entity.buildPanelLogic
    pcall(function() logic:autoPopulateInputs() end)
    local okCan, can = pcall(function() return logic:canPerformCurrentRecipe() end)
    return entity, _player:isBuildCheat() or (okCan and can == true)
end

local function onBuildThis(_player, _entry)
    local entity, can = realEntity(_player, _entry)
    if entity == nil then return end
    if not can then
        _player:setHaloNote(getText("UI_COOP_Holo_Missing"), 255, 100, 100, 300)
        return
    end
    entity:getSprite()
    local square = getCell():getGridSquare(_entry.x, _entry.y, _entry.z)
    if square == nil or not entity:isValid(square) then
        _player:setHaloNote(getText("UI_COOP_Holo_Blocked"), 255, 100, 100, 300)
        return
    end
    entity:tryBuild(_entry.x, _entry.y, _entry.z)
end

-- ---------------------------------------------------------------------------
-- the right-click menu
-- ---------------------------------------------------------------------------

-- The holograms under the click. The squares of the objects clicked, and the square
-- under the mouse with the two behind it: a wall's sprite stands up from its square,
-- so clicking high on it lands one or two squares north-west of the one it is on.
local function hologramsAt(_playerNum, _worldobjects, _z)
    local squares = {}
    for _, object in ipairs(_worldobjects or {}) do
        local square = object.getSquare and object:getSquare()
        if square then squares[COOPHolo.tileKey(square:getX(), square:getY(), square:getZ())] = true end
    end
    local ok, mx, my = pcall(function()
        return screenToIsoX(_playerNum, getMouseX(), getMouseY(), _z),
            screenToIsoY(_playerNum, getMouseX(), getMouseY(), _z)
    end)
    if ok and mx and my then
        mx, my = math.floor(mx), math.floor(my)
        for k = 0, 2 do squares[COOPHolo.tileKey(mx + k, my + k, _z)] = true end
    end

    local found = {}
    for _, entry in pairs(COOPHoloUI.getEntries()) do
        for _, tile in ipairs(entry.tiles) do
            if squares[COOPHolo.tileKey(tile.x, tile.y, tile.z)] then
                table.insert(found, entry)
                break
            end
        end
    end
    table.sort(found, function(_a, _b) return tonumber(_a.id) < tonumber(_b.id) end)
    return found
end

local function onFillWorldObjectContextMenu(_playerNum, _context, _worldobjects, _test)
    if _test and ISWorldObjectContextMenu.Test then return true end
    if not COOPHolo.isEnabled() then return end

    local player = getSpecificPlayer(_playerNum)
    if player == nil or player:getVehicle() ~= nil then return end

    local found = hologramsAt(_playerNum, _worldobjects, math.floor(player:getZ()))
    if #found == 0 then return end
    if _test then return ISWorldObjectContextMenu.setTest() end

    for _, entry in ipairs(found) do
        local option = _context:addOption(getText("ContextMenu_COOP_Holo", COOPHolo.displayName(entry.name)))
        local sub = ISContextMenu:getNew(_context)
        _context:addSubMenu(option, sub)

        local build = sub:addOption(getText("ContextMenu_COOP_Holo_Build"), player, onBuildThis, entry)
        local _, can = realEntity(player, entry)
        if not can then
            build.notAvailable = true
            local tooltip = ISWorldObjectContextMenu.addToolTip()
            tooltip.description = getText("UI_COOP_Holo_Missing")
            build.toolTip = tooltip
        end
        sub:addOption(getText("ContextMenu_COOP_Holo_Delete"), entry.id, COOPHoloUI.remove)
    end
end

-- ---------------------------------------------------------------------------
-- the button, under Build in the Build window
-- ---------------------------------------------------------------------------

local SPACING = 5

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

local function onHoloButton(self)
    local info = self.logic and self.logic:getSelectedBuildObject()
    COOPHoloUI.startCursor(self.player, info)
end

local function install()
    local any = hook(ISWidgetBuildControl, "createChildren", "holoChildren", function(_original)
        return function(self, ...)
            _original(self, ...)
            local craft = self.buttonCraft
            local button = ISButton:new(0, 0, 48, craft:getHeight(), getText("UI_COOP_Holo_Button"), self, onHoloButton)
            button.font = UIFont.Small
            button:initialise()
            button:instantiate()
            button.textColor = { r = COOPHolo.R, g = COOPHolo.G, b = COOPHolo.B, a = 1 }
            self:addChild(button)
            self.coopHoloButton = button
        end
    end)

    -- Vanilla lays out Build and whatever follows it; the hologram button goes straight
    -- under Build and everything below moves down one row.
    hook(ISWidgetBuildControl, "calculateLayout", "holoLayout", function(_original)
        return function(self, ...)
            _original(self, ...)
            local button = self.coopHoloButton
            if button == nil then return end
            local craft = self.buttonCraft
            local row = button:getHeight() + SPACING
            local below = craft:getY() + craft:getHeight()
            for _, child in ipairs({ self.buttonForceCraft, self.buttonKnowAllRecipes }) do
                if child and child:getY() >= below then child:setY(child:getY() + row) end
            end
            button:setX(craft:getX())
            button:setY(below + SPACING)
            button:setWidth(craft:getWidth())
            button:setVisible(COOPHolo.isEnabled())
            if COOPHolo.isEnabled() then
                self.boxHeight = self.boxHeight + row
                self:setHeight(self:getHeight() + row)
                self:insertNewLineOfButtons(button)
            end
        end
    end)

    hook(ISWidgetBuildControl, "prerender", "holoPrerender", function(_original)
        return function(self, ...)
            _original(self, ...)
            if self.coopHoloButton then
                self.coopHoloButton.enable = self.logic ~= nil and self.logic:getSelectedBuildObject() ~= nil
            end
        end
    end)

    if any then COOP.log("hologram button ready") end
end

install()
Events.OnGameBoot.Add(install)
Events.OnGameStart.Add(install)

Events.OnServerCommand.Add(onServerCommand)
Events.OnTick.Add(onTick)
Events.RenderOpaqueObjectsInWorld.Add(onRenderOpaqueObjectsInWorld)
Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
Events.OnCreatePlayer.Add(function()
    synced = false
    nextRequestMs = 0
end)
