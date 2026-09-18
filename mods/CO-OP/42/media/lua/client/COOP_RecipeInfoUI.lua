--
-- CO-OP - the "what you get" row in the crafting window.
--
-- One extra row in the selected recipe's panel, between the outputs and the Craft
-- button, listing the XP the recipe awards and the stats the item it produces will
-- have. The numbers come from COOP_RecipeInfo.lua; this file is the widget and the
-- hook that puts it on screen.
--

require "ISUI/ISPanel"

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)

-- ---------------------------------------------------------------------------
-- the widget
--
-- Deliberately not built out of ISLabel children the way vanilla's
-- ISCraftRecipeInfoBox is. A cell in an ISTableLayout only ever has
-- calculateLayout / getWidth / getHeight / setX / setY / setVisible called on it, so a
-- plain panel that draws its own two columns is the whole contract, and it needs no
-- ISXuiSkin plumbing to be built from.
-- ---------------------------------------------------------------------------

COOPRecipeInfoWidget = ISPanel:derive("COOPRecipeInfoWidget")

local PAD = 4
local LINE = FONT_HGT_SMALL + 2

-- The bar column. Wide enough to read a proportion off at a glance, narrow enough that
-- the figure still fits beside it in the panel.
local BAR_WIDTH = 70
local BAR_HEIGHT = FONT_HGT_SMALL - 4

-- Red at empty, green at full, exactly as the item's own tooltip colours the same bars:
-- HandWeapon.DoTooltip hands ColorInfo.interp the bad colour, the fraction and the good
-- one, i.e. a straight lerp from one to the other.
local function barColour(_fraction)
    local f = _fraction
    if f < 0 then f = 0 elseif f > 1 then f = 1 end

    local bad = getCore():getBadHighlitedColor()
    local good = getCore():getGoodHighlitedColor()

    return {
        r = bad:getR() + (good:getR() - bad:getR()) * f,
        g = bad:getG() + (good:getG() - bad:getG()) * f,
        b = bad:getB() + (good:getB() - bad:getB()) * f,
        a = 1,
    }
end

function COOPRecipeInfoWidget:initialise()
    ISPanel.initialise(self)
end

-- Flattens the info table into the rows we draw, so render() does no thinking.
function COOPRecipeInfoWidget:buildRows()
    self.rows = {}
    self.anyBars = false

    local info = self.info
    if info == nil then return end

    if #info.xp > 0 then
        local label = getText("UI_COOP_RecipeInfo_Xp")
        for _, award in ipairs(info.xp) do
            table.insert(self.rows, {
                label = label,
                value = string.format("%s  +%d", award.perk, award.amount),
                good = true,
            })
            -- several perks share the one label, listed under it
            label = ""
        end
    end

    -- The item's name is only worth a heading when there is more than one item with
    -- stats: with a single output the row above already shows what it is.
    local named = #info.outputs > 1

    for _, output in ipairs(info.outputs) do
        if named then
            local name = output.name
            if output.alternatives > 0 then
                -- tostring, because getText takes Objects: a bare Lua number crosses as
                -- a Double and would substitute in as "2.0"
                name = name .. " " .. getText("UI_COOP_RecipeInfo_OrOthers",
                        tostring(output.alternatives))
            end
            table.insert(self.rows, { label = name, value = "", heading = true })
        end

        for _, line in ipairs(output.lines) do
            table.insert(self.rows, {
                label = line.label .. ":",
                value = line.value,
                fraction = line.fraction,
            })
            if line.fraction ~= nil then self.anyBars = true end
        end
    end
end

function COOPRecipeInfoWidget:calculateLayout(_preferredWidth, _preferredHeight)
    local width = math.max(self.minimumWidth or 0, _preferredWidth or 0)

    -- The label column is as wide as its widest entry, so the two columns line up
    -- whatever mix of XP and stats this recipe happens to have.
    --
    -- The two widths are tracked separately and added at the end rather than taking the
    -- widest label+value pair: the values all start at the same x, so a short label with
    -- a long value needs the *widest* label plus its own value, which a per-row total
    -- would under-report and then clip.
    local labelWidth = 0
    local valueWidth = 0
    for _, row in ipairs(self.rows or {}) do
        labelWidth = math.max(labelWidth,
                getTextManager():MeasureStringX(UIFont.Small, row.label))
        valueWidth = math.max(valueWidth,
                getTextManager():MeasureStringX(UIFont.Small, row.value))
    end

    self.labelWidth = labelWidth
    -- The bar column is reserved for the whole block as soon as one row wants a bar,
    -- so that the figures beside the bars stay in one line with the figures without.
    self.barColumn = self.anyBars and (BAR_WIDTH + PAD * 2) or 0
    width = math.max(width, labelWidth + self.barColumn + valueWidth + PAD * 4)

    local height = PAD * 2 + (#(self.rows or {}) * LINE)
    height = math.max(self.minimumHeight or 0, height, _preferredHeight or 0)

    self:setWidth(width)
    self:setHeight(height)
end

function COOPRecipeInfoWidget:render()
    ISPanel.render(self)

    local barX = PAD + self.labelWidth + PAD * 2
    local valueX = barX + (self.barColumn or 0)

    local y = PAD
    for _, row in ipairs(self.rows or {}) do
        if row.heading then
            self:drawText(row.label, PAD, y, 0.85, 0.85, 0.75, 1, UIFont.Small)
        else
            if row.label ~= "" then
                self:drawText(row.label, PAD, y, 0.62, 0.62, 0.62, 1, UIFont.Small)
            end

            if row.fraction ~= nil then
                -- centred on the text line, so the bar sits with the figure beside it
                self:drawProgressBar(barX, y + (FONT_HGT_SMALL - BAR_HEIGHT) / 2,
                        BAR_WIDTH, BAR_HEIGHT, row.fraction, barColour(row.fraction))
            end

            if row.good then
                self:drawText(row.value, valueX, y,
                        self.colGood.r, self.colGood.g, self.colGood.b, 1, UIFont.Small)
            else
                self:drawText(row.value, valueX, y, 0.92, 0.92, 0.92, 1, UIFont.Small)
            end
        end
        y = y + LINE
    end
end

function COOPRecipeInfoWidget:new(_x, _y, _width, _height, _info)
    local o = ISPanel.new(self, _x, _y, _width, _height)
    o.background = false
    o.info = _info
    o.margin = 0
    o.minimumWidth = 0
    o.minimumHeight = 0
    o.labelWidth = 0
    o.barColumn = 0

    local good = getCore():getGoodHighlitedColor()
    o.colGood = { r = good:getR(), g = good:getG(), b = good:getB() }

    o:buildRows()
    return o
end

-- ---------------------------------------------------------------------------
-- the hook
--
-- Same re-checking discipline as the output pickers: a mod that requires a vanilla
-- class file makes the game load it early, and the normal file scan then loads it
-- again, replacing the class table and dropping anything attached to the old one. So
-- this file requires no vanilla crafting file, and install() re-wraps whenever the
-- class no longer carries our function.
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

-- Puts our widget in the craft control's row and moves the craft control down into a
-- new one, so the numbers sit above the Craft button rather than under it.
--
-- createDynamicChildren always finishes with the craft control in the last row, but
-- that is vanilla's running order rather than a promise, so it is checked: if the last
-- row turns out to hold something else, our row is simply appended and the layout is
-- still correct, only lower down.
local function insertRow(_panel, _widget)
    local layout = _panel.rootTable
    if layout == nil then return false end

    local rowCount = layout:rowCount()
    if rowCount <= 0 then return false end

    local lastIndex = rowCount - 1
    local lastCell = layout:cell(0, lastIndex)
    local craftControl = _panel.craftControl

    if craftControl ~= nil and lastCell ~= nil and lastCell.element == craftControl then
        local row = layout:addRow()
        layout:setElement(0, lastIndex, _widget)
        layout:setElement(0, row:index(), craftControl)
    else
        local row = layout:addRow()
        layout:setElement(0, row:index(), _widget)
    end

    return true
end

local function install()
    local any = false

    any = hook(ISCraftRecipePanel, "createDynamicChildren", "recipeInfo", function(_original)
        return function(self)
            _original(self)

            -- Everything of ours runs inside the pcall, the feature switch included:
            -- this is vanilla's own createDynamicChildren, and an error escaping here
            -- takes the whole recipe panel down with it.
            local ok = pcall(function()
                if not COOP.featureEnabled(COOP.F_RECIPEINFO) then return end
                if self.rootTable == nil or self.logic == nil then return end

                local recipe = self.logic:getRecipe()
                if recipe == nil then return end

                local info = COOPRecipeInfo.forRecipe(recipe)
                if info == nil then return end

                local widget = COOPRecipeInfoWidget:new(0, 0, 10, 10, info)
                widget:initialise()
                widget:instantiate()

                if insertRow(self, widget) then
                    self.coopRecipeInfo = widget
                    -- the table has a new row, so the panel has to measure again
                    self:xuiRecalculateLayout()
                end
            end)

            if not ok then COOP.log("recipeinfo: could not build the row") end
        end
    end) or any

    if any then COOP.log("recipe info row installed") end
end

install()
Events.OnGameBoot.Add(install)
Events.OnGameStart.Add(install)
