--
-- CO-OP - putting the quantity spinner back on recipes vanilla makes you craft one at
-- a time. Which recipes those are is COOP_BatchCraft.lua's business; this file is only
-- the hook.
--

-- ---------------------------------------------------------------------------
-- the hook
--
-- `ISCraftRecipePanel:createDynamicChildren` sets the flag:
--
--     self.craftControl.allowBatchCraft = recipe:isAllowBatchCraft();
--     self.craftControl:initialise();
--
-- and that line is the *only* place in the game, Lua or Java, that reads the script
-- flag - checked against every class in the jar, where the only mentions outside
-- CraftRecipe itself are in the script-generator tooling. Nothing downstream enforces
-- it, because a batch is not a special kind of craft: ISEntityUI.HandcraftStartMultiple
-- just queues that many ordinary actions. So setting the field is the whole feature.
--
-- We wrap `initialise` rather than `createDynamicChildren`, and that choice matters.
-- Two files in this mod already wrap functions here - COOP_RecipeInfoUI takes
-- `ISCraftRecipePanel:createDynamicChildren`, COOP_OutputUI takes this widget's
-- `createChildren`, `prerender` and `calculateLayout`. Two of our files wrapping the
-- *same* function would break the re-checking `hook` discipline outright: each file
-- remembers only its own wrapper, so after the other one wraps on top, the first no
-- longer recognises what is installed and wraps again on the next OnGameBoot. The chain
-- grows every boot and every layer runs its own body - which for the recipe info row
-- would mean a second copy of it on every craft. `initialise` is wrapped by nothing
-- else, and `allowBatchCraft` is set immediately before it is called, so it is exactly
-- the right moment.
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

local function install()
    local any = false

    any = hook(ISWidgetHandCraftControl, "initialise", "batchCraft", function(_original)
        return function(self)
            -- Ours first, then vanilla's: initialise is what builds the widgets whose
            -- visibility the flag drives. Wrapped in a pcall so that a recipe we cannot
            -- read leaves the window exactly as vanilla built it.
            pcall(function()
                if self.allowBatchCraft == true then return end
                if self.logic == nil then return end

                local recipe = self.logic:getRecipe()
                if COOPBatchCraft.allows(recipe) then
                    self.allowBatchCraft = true
                end
            end)

            return _original(self)
        end
    end) or any

    if any then COOP.log("batch craft installed") end
end

install()
Events.OnGameBoot.Add(install)
Events.OnGameStart.Add(install)
