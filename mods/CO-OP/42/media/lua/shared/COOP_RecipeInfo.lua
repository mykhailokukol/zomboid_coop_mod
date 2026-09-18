--
-- CO-OP - what a recipe will give you: the XP it awards, and the stats of the item it
-- produces, read before anything is crafted.
--
-- Both questions are answered off the *script* side of the game, because the item does
-- not exist yet. That is not quite enough on its own - see `probe` below - so the second
-- half of the stats comes from one throwaway instance per item type, built once and
-- remembered as a plain table of numbers.
--
-- Data only. The widget that shows it is COOP_RecipeInfoUI.lua.
--

COOPRecipeInfo = COOPRecipeInfo or {}

COOPRecipeInfo.debug = false

local function log(_msg)
    if COOPRecipeInfo.debug then COOP.log("recipeinfo: " .. tostring(_msg)) end
end

-- ---------------------------------------------------------------------------
-- XP
-- ---------------------------------------------------------------------------

-- The XP a recipe hands out, as { { perk = "Carpentry", amount = 40 }, ... }.
--
-- This is a list, not a single value: `xpAward = Woodwork:40;Tailoring:40` is a real
-- vanilla line (recipes_carpentry.txt), so index 0 is not always the whole story.
--
-- Note these are the *awarded* perks, which are a different list from the *required*
-- ones (getRequiredSkill / getRequiredSkillCount) and need not name the same skills.
function COOPRecipeInfo.xpAwards(_recipe)
    local awards = {}
    if _recipe == nil then return awards end

    pcall(function()
        local count = _recipe:getXPAwardCount()
        if count == nil or count <= 0 then return end

        for i = 0, count - 1 do
            local award = _recipe:getXPAward(i)
            if award ~= nil then
                local amount = award:getAmount()
                local name = nil

                -- getPerk() hands back the Perk object itself, so there is no
                -- Perks.FromString round trip to get wrong here. A modded perk can
                -- still fail to name itself, hence the pcall.
                -- tostring() only once a nil has been ruled out: tostring(nil) is the
                -- string "nil", which would read as a perk called nil and stop the
                -- fallback below from ever running.
                local perk = award:getPerk()
                if perk ~= nil then
                    pcall(function()
                        local perkName = perk:getName()
                        if perkName ~= nil then name = tostring(perkName) end
                    end)
                    if name == nil or name == "" then
                        pcall(function()
                            local perkId = perk:getId()
                            if perkId ~= nil then name = tostring(perkId) end
                        end)
                    end
                end

                if amount ~= nil and amount > 0 then
                    table.insert(awards, { perk = name or "?", amount = amount })
                end
            end
        end
    end)

    return awards
end

-- ---------------------------------------------------------------------------
-- the item a recipe produces
-- ---------------------------------------------------------------------------

-- Every item a recipe can produce, as script Item objects.
--
-- getPossibleResultItems() is plural because an output can be mapped (vanilla's
-- `mapper:bowlType` and friends), so one output line can stand for several item types.
-- We describe the first of them and say how many others there were.
function COOPRecipeInfo.outputItems(_recipe)
    local items = {}
    if _recipe == nil then return items end

    pcall(function()
        local outputs = _recipe:getOutputs()
        if outputs == nil then return end

        for i = 0, outputs:size() - 1 do
            local output = outputs:get(i)

            -- Fluids and heat are outputs too, and have none of the stats below.
            local isItem = false
            pcall(function()
                isItem = output:getResourceType() == ResourceType.Item
            end)

            if isItem and not output:isAutomationOnly() then
                local possible = nil
                pcall(function() possible = output:getPossibleResultItems() end)

                if possible ~= nil and possible:size() > 0 then
                    table.insert(items, {
                        script = possible:get(0),
                        alternatives = possible:size() - 1,
                    })
                end
            end
        end
    end)

    return items
end

-- ---------------------------------------------------------------------------
-- stats
--
-- The script item (zombie.scripting.objects.Item) answers condition, damage, weight,
-- insulation and wind resistance, but it has *no* getter at all for sharpness, tree
-- damage or any of the three clothing defenses - the setters exist on it, the getters
-- live on InventoryItem / HandWeapon / Clothing, i.e. only on a real instance. Checked
-- against the class files rather than guessed.
--
-- So one instance per item type is built, read, and dropped on the floor. It is never
-- put in a container or on a square, so nothing about it reaches the world or the save.
-- What is kept is the table of numbers below, because building an item every time the
-- selected recipe changes would be work for nothing.
--
-- Beware the spelling either side of that split: the script item says getWindresist(),
-- Clothing says getWindresistance().
-- ---------------------------------------------------------------------------

local statCache = {}

-- What a full bar means, per stat.
--
-- DAMAGE_SCALE is vanilla's: HandWeapon.DoTooltip fills its damage bar with
-- (minDamage + maxDamage) / 5. The heaviest thing in the game comes to about 1.2 of
-- that, so the top of the bar is deliberately out of reach.
--
-- The two condition scales are the mod's own and the only invented numbers here, for
-- the reason spelt out at the condition line below. They are set from the vanilla item
-- scripts: weapons and tools declare a ConditionMax from 1 to 30, clothing uses 0-100.
local DAMAGE_SCALE = 5.0
local CONDITION_SCALE = 30.0
local CLOTHING_CONDITION_SCALE = 100.0

local function number(_fn)
    local ok, value = pcall(_fn)
    if not ok or value == nil then return nil end
    value = tonumber(value)
    if value == nil or value ~= value then return nil end
    return value
end

-- The "does this item even have one of those" tests are themselves not on every item,
-- so they are asked the same guarded way as the numbers they guard.
local function flag(_fn)
    local ok, value = pcall(_fn)
    return ok and value == true
end

-- Everything the script itself will answer. Always available, needs no instance.
local function fromScript(_scriptItem, _stats)
    local stats = _stats

    stats.condition = number(function() return _scriptItem:getConditionMax() end)
    stats.weight = number(function() return _scriptItem:getActualWeight() end)
    stats.minDamage = number(function() return _scriptItem:getMinDamage() end)
    stats.maxDamage = number(function() return _scriptItem:getMaxDamage() end)
    stats.doorDamage = number(function() return _scriptItem:getDoorDamage() end)
    stats.insulation = number(function() return _scriptItem:getInsulation() end)
    stats.windResist = number(function() return _scriptItem:getWindresist() end)

    pcall(function()
        local location = _scriptItem:getBodyLocation()
        if location ~= nil then
            local text = tostring(location)
            if text ~= "" then stats.bodyLocation = text end
        end
    end)

    -- Without an instance to ask, what kind of thing this is has to be inferred. Both
    -- of these are what the stats themselves say: something that deals damage is a
    -- weapon, something that goes on a body location is clothing.
    stats.isWeapon = (stats.maxDamage ~= nil and stats.maxDamage > 0)
    stats.isClothing = (stats.bodyLocation ~= nil)
end

-- Overlays what only a real instance knows.
--
-- `instanceItem` is the engine's own global for building one from an item type - 78
-- vanilla Lua files use it, `ISFluidItemsViewPanel` with this exact
-- `instanceItem(scriptItem:getFullName())` shape. Note it is *not*
-- `InventoryItemFactory.CreateItem`: that class is real, but it is not in
-- `LuaManager$Exposer`'s list, so calling it from Lua throws and the item never
-- appears. That was the first attempt, and because the call sat inside a pcall it
-- failed completely silently - the XP line showed and no stat line ever did.
local function fromInstance(_fullName, _stats)
    local stats = _stats

    local item = nil
    local built = pcall(function() item = instanceItem(_fullName) end)
    if not built or item == nil then
        log("no instance of " .. tostring(_fullName) .. ", script values only")
        return
    end

    -- capital I on both: the engine's own spelling, and Kahlua is case sensitive.
    -- These two are the engine's own instanceof tests (InventoryItem.IsWeapon returns
    -- false, HandWeapon.IsWeapon returns true, and the same pair for Clothing), so once
    -- there is an instance they are the answer and the guesses below are thrown away.
    local isWeapon = flag(function() return item:IsWeapon() end)
    local isClothing = flag(function() return item:IsClothing() end)
    stats.isWeapon = isWeapon
    stats.isClothing = isClothing

    if flag(function() return item:hasHeadCondition() end) then
        stats.headCondition = number(function() return item:getHeadConditionMax() end)
    end

    if flag(function() return item:hasSharpness() end) then
        stats.sharpness = number(function() return item:getSharpness() end)
        stats.maxSharpness = number(function() return item:getMaxSharpness() end)
    end

    if isWeapon then
        stats.treeDamage = number(function() return item:getTreeDamage() end)
    end

    if isClothing then
        stats.biteDefense = number(function() return item:getBiteDefense() end)
        stats.scratchDefense = number(function() return item:getScratchDefense() end)
        stats.bulletDefense = number(function() return item:getBulletDefense() end)
        -- Clothing spells this one differently from the script item
        stats.windResist = number(function() return item:getWindresistance() end)
                or stats.windResist
    end
end

-- Everything worth knowing about an item type, as a plain table of numbers - never the
-- item, which is read and then dropped on the floor. It is never put in a container or
-- on a square, so nothing about it reaches the world or the save.
local function probe(_scriptItem)
    if _scriptItem == nil then return {} end

    local fullName = COOPRecipeInfo.fullName(_scriptItem)
    if fullName == nil then return {} end

    local cached = statCache[fullName]
    if cached ~= nil then return cached end

    local stats = {}

    -- The script half first, so that a failure to build an instance costs only the
    -- handful of stats the script cannot answer rather than the whole row.
    if not pcall(function() fromScript(_scriptItem, stats) end) then
        log("could not read the script item for " .. tostring(fullName))
    end

    if not pcall(function() fromInstance(fullName, stats) end) then
        log("could not read an instance of " .. tostring(fullName))
    end

    statCache[fullName] = stats
    return stats
end

-- The item type, "Base.Axe" style, off a script item.
function COOPRecipeInfo.fullName(_scriptItem)
    if _scriptItem == nil then return nil end
    local ok, name = pcall(function() return _scriptItem:getFullName() end)
    if ok and name ~= nil and name ~= "" then return tostring(name) end
    return nil
end

-- The name to show for the produced item.
function COOPRecipeInfo.displayName(_scriptItem)
    if _scriptItem == nil then return "?" end
    local ok, name = pcall(function() return _scriptItem:getDisplayName() end)
    if ok and name ~= nil and name ~= "" then return tostring(name) end
    return COOPRecipeInfo.fullName(_scriptItem) or "?"
end

-- Everything worth saying about what one output item will be.
--
-- Deliberately answers nothing at all for a plank, a nail or a cooked meal: the stats
-- below are the ones that differ between one crafted thing and another, and a line
-- reading "Weight: 0.3" on every recipe in the game is noise. Same principle as the
-- hotbar columns, which draw nothing while every status is green.
function COOPRecipeInfo.statLines(_scriptItem)
    local lines = {}
    if _scriptItem == nil then return lines end

    local stats = probe(_scriptItem)

    -- Weapon or clothing, nothing else. There is no "has a condition" test to widen
    -- this with: `conditionMax` is initialised to 10 in the constructor of both the
    -- script item and InventoryItem, and most items never declare it - so a box of
    -- nails answers 10 as readily as an axe does, and gating on the number would put
    -- "Condition: 10" under every plank, bowl of soup and lump of clay in the game.
    -- IsWeapon/IsClothing are the engine's own class tests and are the honest question.
    if not stats.isWeapon and not stats.isClothing then
        return lines
    end

    -- _fraction, when given, is what fills the bar: 0 draws it red, 1 green, exactly
    -- the way the item's own tooltip draws the same stat. A line with no fraction has
    -- no meaningful 0..1 scale and is left as a plain number.
    local function add(_key, _value, _fraction)
        table.insert(lines, {
            label = getText(_key),
            value = _value,
            fraction = _fraction,
        })
    end

    -- Condition is the one number every one of these has. A two-part tool (an axe head
    -- on a handle) keeps them apart exactly as the hotbar columns do.
    --
    -- The bar here is the one the mod has to invent. Vanilla's tooltip fills it with
    -- `getCondition() / getConditionMax()`, which for something about to be made is
    -- always 1 - a full green bar on every recipe in the game, saying only "it will be
    -- new". What is worth comparing before you craft is how much condition the thing
    -- has *in total*, so the bar is the max against CONDITION_SCALE and the number
    -- beside it is the figure itself.
    if stats.condition ~= nil and stats.condition > 0 then
        local scale = stats.isClothing and CLOTHING_CONDITION_SCALE or CONDITION_SCALE
        if stats.headCondition ~= nil and stats.headCondition > 0 then
            add("Tooltip_weapon_HandleCondition", string.format("%d", stats.condition),
                    stats.condition / scale)
            add("Tooltip_weapon_HeadCondition", string.format("%d", stats.headCondition),
                    stats.headCondition / scale)
        else
            add("Tooltip_weapon_Condition", string.format("%d", stats.condition),
                    stats.condition / scale)
        end
    end

    -- Vanilla's own formula, read out of HandWeapon.DoTooltip: the bar is
    -- (min + max) / 5, so the two figures share one bar and the number carries the
    -- range. Nothing in the game reaches 5, which is why the top of the bar is empty.
    if stats.maxDamage ~= nil and stats.maxDamage > 0 then
        add("Tooltip_weapon_Damage",
                string.format("%.2f - %.2f", stats.minDamage or 0, stats.maxDamage),
                ((stats.minDamage or 0) + stats.maxDamage) / DAMAGE_SCALE)
    end

    -- Sharpness is already a fraction, and vanilla bars it directly.
    if stats.maxSharpness ~= nil and stats.maxSharpness > 0 then
        add("Tooltip_weapon_Sharpness", string.format("%.2f", stats.sharpness or 0),
                (stats.sharpness or 0) / stats.maxSharpness)
    end

    -- No scale to speak of for these two, so no bar.
    if stats.treeDamage ~= nil and stats.treeDamage > 0 then
        add("UI_COOP_RecipeInfo_TreeDamage", string.format("%d", stats.treeDamage))
    end

    if stats.doorDamage ~= nil and stats.doorDamage > 0 then
        add("UI_COOP_RecipeInfo_DoorDamage", string.format("%d", stats.doorDamage))
    end

    -- The three defenses are percentages, so the bar is simply that.
    if stats.biteDefense ~= nil and stats.biteDefense > 0 then
        add("Tooltip_BiteDefense", string.format("%d%%", stats.biteDefense),
                stats.biteDefense / 100)
    end
    if stats.scratchDefense ~= nil and stats.scratchDefense > 0 then
        add("Tooltip_ScratchDefense", string.format("%d%%", stats.scratchDefense),
                stats.scratchDefense / 100)
    end
    if stats.bulletDefense ~= nil and stats.bulletDefense > 0 then
        add("Tooltip_BulletDefense", string.format("%d%%", stats.bulletDefense),
                stats.bulletDefense / 100)
    end
    if stats.insulation ~= nil and stats.insulation > 0 then
        add("Tooltip_item_Insulation", string.format("%.2f", stats.insulation),
                stats.insulation)
    end
    if stats.windResist ~= nil and stats.windResist > 0 then
        add("Tooltip_item_Windresist", string.format("%.2f", stats.windResist),
                stats.windResist)
    end

    -- Weight is a figure, not a proportion of anything, so it stays a figure - which
    -- is also how the item's own tooltip shows it.
    if stats.weight ~= nil and stats.weight > 0 then
        add("Tooltip_item_Weight", string.format("%.2f", stats.weight))
    end

    return lines
end

-- Everything the widget draws, in one call: the XP awards and one block per output
-- item that has anything to say. Returns nil when there is nothing at all to show.
function COOPRecipeInfo.forRecipe(_recipe)
    if _recipe == nil then return nil end

    local info = {
        xp = COOPRecipeInfo.xpAwards(_recipe),
        outputs = {},
    }

    for _, output in ipairs(COOPRecipeInfo.outputItems(_recipe)) do
        local lines = COOPRecipeInfo.statLines(output.script)
        if #lines > 0 then
            table.insert(info.outputs, {
                name = COOPRecipeInfo.displayName(output.script),
                alternatives = output.alternatives,
                lines = lines,
            })
        end
    end

    if #info.xp == 0 and #info.outputs == 0 then return nil end
    return info
end
