--
-- CO-OP - crafting more than one of something at a time.
--
-- 111 vanilla recipes declare `AllowBatchCraft = false`, which hides the quantity
-- spinner and the MAX button in the crafting window. 85 of them are tailoring: every
-- craftable garment and bag, so working Tailoring up means clicking Craft once per
-- shirt. This puts the spinner back for those, and leaves it off for the rest.
--
-- Data only. The hook that applies it is COOP_BatchCraftUI.lua.
--

COOPBatchCraft = COOPBatchCraft or {}

COOPBatchCraft.debug = false

local function log(_msg)
    if COOPBatchCraft.debug then COOP.log("batchcraft: " .. tostring(_msg)) end
end

-- ---------------------------------------------------------------------------
-- which recipes may be batched
--
-- The flag covers two quite different kinds of recipe and only one of them may be
-- turned back on:
--
--   production - fabric and thread in, a shirt out. Nothing in the engine objects to
--                doing it five times; a batch is not one action making five things, it
--                is five ordinary actions queued, each building its own HandcraftLogic
--                and picking its own inputs when its turn comes.
--
--   transform  - FixWithDuctTape, PutFilterOnGasMask, OpenBottleOfWine, RollOneDice.
--                These work on one item the player already has, kept rather than
--                consumed. Batching them is meaningless, and worse: when every input
--                is `mode:keep`, CraftRecipeData.getInputCraftCount short-circuits to
--                MAX_CRAFT_COUNT, so MAX would offer to repair the same axe 100 times.
--                That short circuit is very likely why the flag exists at all.
--
-- Telling them apart took some looking. The obvious tests do not work: `InputFlag.
-- FakeOutput` is used by exactly zero vanilla recipes, no recipe among the 111 uses a
-- `+`/`-` continuation line (so getCreateToItemScript is always nil), and `isKeep` is
-- true somewhere in 107 of the 111 because scissors, needle and awl are all kept tools.
--
-- What does separate them, on all 111:
--
--   * a transform usually has no outputs at all - the work happens in an OnCreate
--     function against the kept item;
--   * the three that do have outputs (RemoveBattery, OpenBottleOfWine,
--     RemovePropaneBottle) are all "take a part out of a kept device", and each marks
--     the kept item with a flag that says the recipe changes its state.
--
-- So: something must come out, and nothing kept may be altered on the way.
-- ---------------------------------------------------------------------------

-- Flags on a kept input meaning "this recipe modifies that item". A kept input without
-- one of these is an ordinary tool.
COOPBatchCraft.TRANSFORM_FLAGS = {
    "Unseal",               -- OpenBottleOfWine
    "NotEmpty",             -- RemoveBattery, RemovePropaneBottle
    "InheritUses",
    "InheritUsesAndEmpty",  -- both of the above
}

local function mutatesAKeptItem(_recipe)
    local mutates = false

    pcall(function()
        local inputs = _recipe:getInputs()
        if inputs == nil then return end

        for i = 0, inputs:size() - 1 do
            local input = inputs:get(i)
            if input ~= nil and input:isKeep() then
                for _, name in ipairs(COOPBatchCraft.TRANSFORM_FLAGS) do
                    local flag = InputFlag[name]
                    if flag ~= nil and input:hasFlag(flag) then
                        mutates = true
                        return
                    end
                end
            end
        end
    end)

    return mutates
end

local function producesSomething(_recipe)
    local produces = false

    pcall(function()
        local outputs = _recipe:getOutputs()
        if outputs == nil then return end

        for i = 0, outputs:size() - 1 do
            local output = outputs:get(i)
            -- an automation-only output never appears in the hand-crafting window
            if output ~= nil and not output:isAutomationOnly() then
                produces = true
                return
            end
        end
    end)

    return produces
end

-- True when the mod should put the quantity spinner back for this recipe.
function COOPBatchCraft.allows(_recipe)
    if _recipe == nil then return false end
    if not COOP.featureEnabled(COOP.F_BATCHCRAFT) then return false end

    -- already batchable; nothing for us to do
    local vanilla = false
    pcall(function() vanilla = _recipe:isAllowBatchCraft() == true end)
    if vanilla then return false end

    if not producesSomething(_recipe) then
        log("no outputs, leaving alone: " .. tostring(COOPBatchCraft.nameOf(_recipe)))
        return false
    end

    if mutatesAKeptItem(_recipe) then
        log("changes a kept item, leaving alone: "
                .. tostring(COOPBatchCraft.nameOf(_recipe)))
        return false
    end

    log("batching enabled for " .. tostring(COOPBatchCraft.nameOf(_recipe)))
    return true
end

-- For the log only.
function COOPBatchCraft.nameOf(_recipe)
    if _recipe == nil then return "?" end
    local ok, name = pcall(function() return _recipe:getName() end)
    if ok and name ~= nil then return tostring(name) end
    return "?"
end
