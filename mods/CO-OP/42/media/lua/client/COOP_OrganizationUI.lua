--
-- CO-OP - the Organization skill, client side.
--
--   * converts the Organized / Disorganized traits into a starting level, once
--   * awards XP for the weight moved in and out of containers
--   * keeps the Dextrous / All Thumbs traits in step with the level, on both peers
--   * raises the capacity of containers the player opens
--

if isServer() then return end

require "COOP_Common"
require "COOP_Organization"

local installed = {}
local lastLevel = nil
local pendingXpSync = 0

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

-- ---------------------------------------------------------------------------
-- level, traits and the server's copy of them
-- ---------------------------------------------------------------------------

local function syncLevel(_playerObj)
    if _playerObj == nil then return end

    local level = COOPOrg.getLevel(_playerObj)
    lastLevel = level

    COOPOrg.applyTraits(_playerObj, level)

    if isClient() then
        local modData = _playerObj:getModData()
        sendClientCommand(_playerObj, COOPOrg.MODULE, COOPOrg.CMD_LEVEL, {
            level = level,
            xp = COOPOrg.getXp(_playerObj),
            init = modData[COOPOrg.INIT_KEY] == true,
            startLevel = modData[COOPOrg.START_LEVEL_KEY],
        })
    end
end

-- Organized / Disorganized decide where the character starts, then get out of the way.
local function setupCharacter(_playerObj)
    if _playerObj == nil then return end

    local modData = _playerObj:getModData()

    -- XP already banked means this character was set up before, whatever the flag says:
    -- in multiplayer the flag itself only reaches the save through the sync below, and
    -- re-running the setup would reset the character to its starting level.
    if modData[COOPOrg.INIT_KEY] ~= true and COOPOrg.getXp(_playerObj) > 0 then
        modData[COOPOrg.INIT_KEY] = true
    end

    if modData[COOPOrg.INIT_KEY] ~= true then
        local level = COOPOrg.DEFAULT_LEVEL

        local ok = pcall(function()
            local traits = _playerObj:getCharacterTraits()
            if _playerObj:hasTrait(CharacterTrait.ORGANIZED) then
                level = COOPOrg.ORGANIZED_LEVEL
                traits:remove(CharacterTrait.ORGANIZED)
            elseif _playerObj:hasTrait(CharacterTrait.DISORGANIZED) then
                level = COOPOrg.DISORGANIZED_LEVEL
                traits:remove(CharacterTrait.DISORGANIZED)
            end
        end)

        if ok then
            modData[COOPOrg.INIT_KEY] = true
            modData[COOPOrg.START_LEVEL_KEY] = level
            COOP.log("Organization starts at level " .. tostring(level))
        end
    end

    -- Levels never drop on their own, so topping back up to the starting level is safe.
    local startLevel = modData[COOPOrg.START_LEVEL_KEY] or COOPOrg.DEFAULT_LEVEL
    if startLevel > 0 and COOPOrg.getLevel(_playerObj) < startLevel then
        COOPOrg.setXp(_playerObj, COOPOrg.totalXpForLevel(startLevel))
        COOP.log("Organization set to level " .. tostring(startLevel))
    end

    syncLevel(_playerObj)
end

-- ---------------------------------------------------------------------------
-- XP from moving things around
-- ---------------------------------------------------------------------------

local function isPlayerSide(_container, _character)
    if _container == nil then return false end
    if _container == _character:getInventory() then return true end
    local ok, inside = pcall(function() return _container:isInCharacterInventory(_character) end)
    return ok and inside == true
end

local function awardXp(_character, _item, _srcContainer, _destContainer)
    if _character == nil or _item == nil then return end
    if _character ~= getPlayer() then return end
    if not COOP.featureEnabled(COOP.F_ORGANIZATION) then return end

    -- Organising is moving things through storage: into it, out of it, or from one
    -- container straight into another. Shuffling inside your own bags, or throwing
    -- things on the floor, teaches nothing.
    if _srcContainer == nil or _destContainer == nil then return end
    if _srcContainer:getType() == "floor" or _destContainer:getType() == "floor" then return end

    local fromPlayer = isPlayerSide(_srcContainer, _character)
    local toPlayer = isPlayerSide(_destContainer, _character)
    if fromPlayer and toPlayer then return end

    local ok, weight = pcall(function() return _item:getActualWeight() end)
    if not ok or weight == nil or weight <= 0 then return end

    local amount = weight * COOPOrg.XP_PER_KG
            * COOP.numberOption("OrganizationXpRate", 1.0, 0.1, 10.0)
    local level, leveledUp = COOPOrg.addXp(_character, amount)

    if COOPOrg.debug then
        local into, needed = COOPOrg.getProgress(_character)
        COOP.log("organization xp: " .. string.format("%.1f", amount)
                .. " for " .. tostring(_item:getFullType())
                .. " level=" .. tostring(level)
                .. " (" .. string.format("%.0f/%d", into, needed) .. ")")
    end

    if leveledUp then
        pcall(function()
            HaloTextHelper.addTextWithArrow(_character,
                    getText("IGUI_perks_Organization") .. " " .. tostring(level),
                    true, HaloTextHelper.getColorGreen())
        end)
    end

    if level ~= lastLevel then
        syncLevel(_character)
    elseif isClient() then
        -- the server's copy is what gets saved, so keep the running total there
        pendingXpSync = (pendingXpSync or 0) + 1
        if pendingXpSync >= 10 then
            pendingXpSync = 0
            syncLevel(_character)
        end
    end
end

-- ---------------------------------------------------------------------------
-- capacity: raise what the player opens
-- ---------------------------------------------------------------------------

local function requestCapacity(_container, _character)
    if _container == nil or _character == nil then return end

    local multiplier = COOPOrg.getMultiplier(_character)
    if multiplier <= 1.0 then return end
    if COOPCart ~= nil and COOPCart.isCartContainer(_container) then return end

    local args = { multiplier = multiplier }

    local item = _container:getContainingItem()
    if item ~= nil then
        args.itemId = item:getID()
    else
        local object = _container:getParent()
        local square = object ~= nil and object:getSquare() or nil
        if square == nil then return end

        args.x = square:getX()
        args.y = square:getY()
        args.z = square:getZ()
        args.containerType = _container:getType()
        args.containerIndex = object:getContainerIndex(_container)

        local objects = square:getObjects()
        for i = 0, objects:size() - 1 do
            if objects:get(i) == object then
                args.objectIndex = i
                break
            end
        end
    end

    if isClient() then
        -- the server owns containers: it works out the new size from the base capacity
        -- it recorded, applies it, and tells everyone
        sendClientCommand(_character, COOPOrg.MODULE, COOPOrg.CMD_CAPACITY, args)
    else
        local wanted = COOPOrg.wantedCapacity(_container, multiplier)
        if wanted ~= nil then COOPOrg.setCapacity(_container, wanted) end
    end
end

local function onServerCommand(_module, _command, _args)
    if _module ~= COOPOrg.MODULE or _command ~= COOPOrg.CMD_CAPACITY then return end

    local container = COOPOrg.resolveContainer(_args, getPlayer())
    if container == nil or _args.capacity == nil then return end

    -- record the original first, so this client never mistakes a raised capacity for it
    if _args.base ~= nil then COOPOrg.rememberBaseCapacity(container, _args.base) end

    -- the server is the authority, including when it repairs a container downwards
    if _args.capacity == container:getCapacity() then return end
    COOPOrg.setCapacity(container, _args.capacity)
end

-- ---------------------------------------------------------------------------
-- the container weight readout
-- ---------------------------------------------------------------------------

local COLOR_BASE = { r = 1.0, g = 0.85, b = 0.2 }   -- what the container holds without the perk
local COLOR_OVER = { r = 1.0, g = 0.35, b = 0.35 }  -- fill is past that

-- Draws "15.4 / 30 / 60" right-aligned at _x, the middle number yellow, the fill red
-- once it passes the middle one. _text is the label vanilla was about to draw.
local function drawCapacityLabel(_page, _text, _x, _y, _base, _capacity, _font)
    local font = _font or UIFont.Small

    local fill = string.match(_text, "^([%d%.]+)")
    if fill == nil then return false end
    -- multiplayer appends " (12 / 50)" for the item-count limit; keep it
    local suffix = string.match(_text, "^[%d%.]+ / [%d%.]+(.*)$") or ""

    local parts = {
        { text = fill, r = 1, g = 1, b = 1 },
        { text = " / ", r = 1, g = 1, b = 1 },
        { text = tostring(_base), r = COLOR_BASE.r, g = COLOR_BASE.g, b = COLOR_BASE.b },
        { text = " / ", r = 1, g = 1, b = 1 },
        { text = tostring(_capacity), r = 1, g = 1, b = 1 },
    }
    if suffix ~= "" then
        table.insert(parts, { text = suffix, r = 1, g = 1, b = 1 })
    end

    local fillValue = tonumber(fill)
    if fillValue ~= nil and fillValue > _base then
        parts[1].r, parts[1].g, parts[1].b = COLOR_OVER.r, COLOR_OVER.g, COLOR_OVER.b
    end

    local total = 0
    for _, part in ipairs(parts) do
        total = total + getTextManager():MeasureStringX(font, part.text)
    end

    local x = _x - total
    for _, part in ipairs(parts) do
        _page:drawText(part.text, x, _y, part.r, part.g, part.b, 1, font)
        x = x + getTextManager():MeasureStringX(font, part.text)
    end

    return true
end

-- ---------------------------------------------------------------------------
-- the row in the skills panel
--
-- ISSkillProgressBar re-reads the level from the engine every frame, and for our perk
-- the engine always says 0, so the row for this perk is drawn here instead.
-- ---------------------------------------------------------------------------

local SKILL_POINT_HGT = math.floor((getTextManager():getFontHeight(UIFont.Small) + 6) / 2)
local SKILL_POINT_SPACING = getCore():getOptionFontSizeReal()
-- the colour vanilla paints gained levels with
local GAINED_R, GAINED_G, GAINED_B = 1, 0.89, 0.38

local function isOurPerk(_perk)
    if _perk == nil then return false end
    local ours = COOPOrg.getPerk()
    return ours ~= nil and _perk == ours
end

-- Same shape as the vanilla row: filled squares for levels gained, a partly filled one
-- for the level in progress, dark empty ones for the rest.
local function drawOurRow(_bar)
    local character = _bar.char
    if character == nil then return end

    local level = COOPOrg.getLevel(character)
    local into, needed = COOPOrg.getProgress(character)

    local x = 0
    local y = 0

    for _ = 1, level do
        _bar:drawTextureScaled(_bar.SkillUnitFilled, x, y, SKILL_POINT_HGT, SKILL_POINT_HGT, 1, GAINED_R, GAINED_G, GAINED_B)
        _bar:drawTextureScaled(_bar.SkillUnitBorder, x, y, SKILL_POINT_HGT, SKILL_POINT_HGT, 1, GAINED_R, GAINED_G, GAINED_B)
        x = x + SKILL_POINT_HGT + SKILL_POINT_SPACING
    end

    if level < 10 then
        local percent = 0
        if needed > 0 then percent = (into / needed) * 100 end
        if percent < 0 then percent = 0 end
        if percent > 100 then percent = 100 end

        _bar:drawTextureScaled(_bar.SkillUnitBorder, x, y, SKILL_POINT_HGT, SKILL_POINT_HGT, 1, 0.4, 0.4, 0.4)
        _bar:drawTextureScaled(_bar.SkillUnitFilled, x, y,
                (SKILL_POINT_HGT / 100) * percent, SKILL_POINT_HGT, 1, 0.4, 0.4, 0.4)
        x = x + SKILL_POINT_HGT + SKILL_POINT_SPACING

        for _ = level + 2, 10 do
            _bar:drawTextureScaled(_bar.SkillUnitBorder, x, y, SKILL_POINT_HGT, SKILL_POINT_HGT, 1, 0.2, 0.2, 0.2)
            x = x + SKILL_POINT_HGT + SKILL_POINT_SPACING
        end
    end
end

-- The vanilla tooltip reads the engine's perk, which knows nothing about this skill,
-- so it is written here from the same numbers the row is drawn from.
local function buildOurTooltip(_bar, _lvlSelected)
    local character = _bar.char
    if character == nil then return end

    local level = COOPOrg.getLevel(character)
    local into, needed = COOPOrg.getProgress(character)
    local name = _bar.perk:getName()

    local message = name .. " " .. xpSystemText.lvl .. " " .. tostring(_lvlSelected + 1)

    if _lvlSelected < level then
        message = message .. " <LINE> " .. xpSystemText.unlocked
    elseif _lvlSelected == level then
        message = message .. " <LINE> " .. getText("IGUI_XP_tooltipxp", round(into, 2), needed)
    else
        message = message .. " <LINE> " .. xpSystemText.locked
    end

    local multiplier = COOPOrg.MULTIPLIER[_lvlSelected + 1]
    if multiplier ~= nil then
        message = message .. " <LINE> " .. getText("UI_COOP_Org_Effect",
                tostring(math.floor(multiplier * 100)))
    end

    local description = getTextOrNull("IGUI_perks_" .. name .. "_Description")
    if description ~= nil and description ~= "" then
        message = message .. " <LINE><LINE> " .. description
    end

    _bar.message = message
end

-- ---------------------------------------------------------------------------
-- hooks
-- ---------------------------------------------------------------------------

local function install()
    local any = false

    any = hook(ISInventoryTransferAction, "perform", "transferPerform", function(_original)
        return function(self)
            local item = self.item
            local src = self.srcContainer
            local dest = self.destContainer
            local result = _original(self)
            pcall(awardXp, self.character, item, src, dest)
            return result
        end
    end) or any

    any = hook(ISInventoryPage, "selectContainer", "selectContainer", function(_original)
        return function(self, _button)
            local result = _original(self, _button)
            if _button ~= nil and _button.inventory ~= nil then
                pcall(requestCapacity, _button.inventory, getSpecificPlayer(self.player))
            end
            return result
        end
    end) or any

    any = hook(ISInventoryPage, "setNewContainer", "setNewContainer", function(_original)
        return function(self, _inventory)
            local result = _original(self, _inventory)
            if _inventory ~= nil then
                pcall(requestCapacity, _inventory, getSpecificPlayer(self.player))
            end
            return result
        end
    end) or any

    -- The weight readout: only containers that have actually been raised get the
    -- extra number, so a vanilla container still reads "30.5 / 50".
    any = hook(ISInventoryPage, "prerender", "inventoryPrerender", function(_original)
        return function(self)
            local container = self.inventoryPane and self.inventoryPane.inventory or nil
            local base = COOPOrg.peekBaseCapacity(container)
            local capacity = self.capacity

            if base == nil or capacity == nil or type(capacity) ~= "number" or base >= capacity then
                return _original(self)
            end

            -- vanilla draws the label in prerender with one drawTextRight call
            local drawn = false
            self.drawTextRight = function(_page, _text, _x, _y, _r, _g, _b, _a, _font)
                if not drawn and type(_text) == "string" and string.find(_text, "^[%d%.]+ / [%d%.]+") then
                    drawn = true
                    if drawCapacityLabel(_page, _text, _x, _y, base, capacity, _font) then return end
                end
                return ISUIElement.drawTextRight(_page, _text, _x, _y, _r, _g, _b, _a, _font)
            end

            local ok, err = pcall(_original, self)
            self.drawTextRight = nil  -- back to the class method

            if not ok then COOP.log("inventory label failed: " .. tostring(err)) end
        end
    end) or any

    -- our own row drawing, and the tooltip text that goes with it
    any = hook(ISSkillProgressBar, "renderPerkRect", "skillRow", function(_original)
        return function(self)
            if not isOurPerk(self.perk) then return _original(self) end
            local ok, err = pcall(drawOurRow, self)
            if not ok then COOP.log("skill row failed: " .. tostring(err)) end
        end
    end) or any

    any = hook(ISSkillProgressBar, "updateTooltip", "skillTooltip", function(_original)
        return function(self, _lvlSelected)
            if not isOurPerk(self.perk) then return _original(self, _lvlSelected) end
            local ok, err = pcall(buildOurTooltip, self, _lvlSelected)
            if not ok then COOP.log("skill tooltip failed: " .. tostring(err)) end
        end
    end) or any

    if any then COOP.log("Organization hooks installed") end
end

install()
Events.OnGameBoot.Add(install)
Events.OnGameStart.Add(install)
Events.OnServerCommand.Add(onServerCommand)
Events.OnCreatePlayer.Add(function(_playerIndex, _playerObj) setupCharacter(_playerObj) end)
