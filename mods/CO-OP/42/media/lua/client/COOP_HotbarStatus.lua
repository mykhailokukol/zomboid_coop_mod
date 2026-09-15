--
-- CO-OP - condition columns behind the hotbar icons.
--
-- Every slot that holds something wearing out gets its background split into one column
-- per status the item actually has, coloured by how much is left:
--
--     75%+ green        25-74% yellow        0-24% red
--
-- An item whose statuses are all green draws nothing, so the hotbar only lights up when
-- something needs attention.
--
-- B42 keeps three separate numbers on an item and each has its own "does this item even
-- have one" test, so the number of columns varies: an axe has all three, a knife has
-- condition and sharpness, a hammer has condition and a head, a flashlight only has
-- condition. The columns split the slot evenly across whatever is there, in a fixed
-- order (condition, head, sharpness) so the positions stay learnable.
--
-- Purely local: nothing is sent anywhere, and it only ever draws.
--

if isServer() then return end

require "COOP_Common"

COOPHotbarStatus = COOPHotbarStatus or {}

-- The bands, as percentages of each status's own maximum.
COOPHotbarStatus.GREEN = 0.75
COOPHotbarStatus.YELLOW = 0.25

-- Behind the item icon, so it has to stay readable.
COOPHotbarStatus.ALPHA = 0.45

local COLOR_GREEN = { r = 0.30, g = 0.78, b = 0.30 }
local COLOR_YELLOW = { r = 0.92, g = 0.78, b = 0.20 }
local COLOR_RED = { r = 0.85, g = 0.25, b = 0.22 }

local function band(_ratio)
    if _ratio >= COOPHotbarStatus.GREEN then return COLOR_GREEN end
    if _ratio >= COOPHotbarStatus.YELLOW then return COLOR_YELLOW end
    return COLOR_RED
end

local function ratio(_value, _max)
    local value = tonumber(_value)
    local max = tonumber(_max)
    if value == nil or max == nil or max <= 0 then return nil end
    if value ~= value or max ~= max then return nil end   -- NaN

    local result = value / max
    if result < 0 then return 0 end
    if result > 1 then return 1 end
    return result
end

-- Condition first because every item has it; on a two-part tool it is the handle.
-- The other two only exist when the item says so - asking a spoon for its sharpness
-- gives a meaningless zero, which would paint the whole hotbar red.
local function statusesOf(_item)
    local statuses = {}
    if _item == nil then return statuses end

    pcall(function()
        local found = ratio(_item:getCondition(), _item:getConditionMax())
        if found ~= nil then table.insert(statuses, found) end
    end)

    pcall(function()
        if _item:hasHeadCondition() then
            local found = ratio(_item:getHeadCondition(), _item:getHeadConditionMax())
            if found ~= nil then table.insert(statuses, found) end
        end
    end)

    pcall(function()
        if _item:hasSharpness() then
            local found = ratio(_item:getSharpness(), _item:getMaxSharpness())
            if found ~= nil then table.insert(statuses, found) end
        end
    end)

    return statuses
end

local function needsAttention(_statuses)
    for _, value in ipairs(_statuses) do
        if value < COOPHotbarStatus.GREEN then return true end
    end
    return false
end

-- Columns are cut from running offsets rather than by adding a width each time, so
-- rounding cannot leave a gap or an overlap between two of them.
local function drawColumns(_hotbar, _x, _y, _width, _height, _statuses)
    local count = #_statuses
    if count == 0 then return end

    for index, value in ipairs(_statuses) do
        local left = math.floor(_width * (index - 1) / count)
        local right = math.floor(_width * index / count)
        local colour = band(value)
        _hotbar:drawRect(_x + left, _y, right - left, _height,
                COOPHotbarStatus.ALPHA, colour.r, colour.g, colour.b)
    end
end

-- Mirrors the layout ISHotbar:render walks: the first slot starts at margins+1 and each
-- one after it steps by the slot width plus the padding.
local function drawAll(_hotbar)
    if not COOP.featureEnabled(COOP.F_HOTBAR) then return end
    if _hotbar.availableSlot == nil or _hotbar.attachedItems == nil then return end

    local slotX = _hotbar.margins + 1
    local slotY = _hotbar.margins + 1

    for i, _ in pairs(_hotbar.availableSlot) do
        local item = _hotbar.attachedItems[i]
        if item ~= nil then
            local statuses = statusesOf(item)
            if needsAttention(statuses) then
                -- inset by one so the slot's own border still reads
                drawColumns(_hotbar, slotX + 1, slotY + 1,
                        _hotbar.slotWidth - 2, _hotbar.slotHeight - 2, statuses)
            end
        end
        slotX = slotX + _hotbar.slotWidth + _hotbar.slotPad
    end
end

-- ---------------------------------------------------------------------------
-- hook
-- ---------------------------------------------------------------------------

local installed = nil

local function install()
    if ISHotbar == nil then return end
    if installed ~= nil and ISHotbar.render == installed then return end

    local original = ISHotbar.render
    if original == nil then return end

    -- Drawn before the original so the columns end up behind the slot border, the
    -- mouse-over highlight and the item icon - a background, as asked for.
    local wrapper = function(self)
        pcall(drawAll, self)
        return original(self)
    end

    ISHotbar.render = wrapper
    installed = wrapper
    COOP.log("hotbar condition columns ready")
end

install()
Events.OnGameBoot.Add(install)
Events.OnGameStart.Add(install)
