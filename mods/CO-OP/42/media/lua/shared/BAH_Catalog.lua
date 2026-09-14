--
-- CO-OP / Books at home - the list of trackable media.
--
-- Built by scanning the game's own data instead of hardcoding names, so anything a
-- mod adds is tracked automatically:
--   * literature that teaches a skill  -> key is the item type, "Base.BookCarpentry1"
--   * literature that teaches recipes  -> same
--   * recordings (VHS) that teach      -> key is "media:<recording id>", because every
--     Home-VHS tape shares one item type and only the recording differs
--

require "BAH_Common"

local catalog = nil  -- key -> entry
local order = nil    -- display-ordered array of the same entries

local MEDIA_PREFIX = "media:"

-- Media line code -> perk, taken from the doSkill() entries of the game's own
-- media/lua/shared/RadioCom/ISRadioInteractions.lua. Codes not listed here are
-- moodle effects (boredom, stress, ...) and do not make a recording educational.
local MEDIA_SKILL_CODES = {
    SPR = "Sprinting", LFT = "Lightfoot", NIM = "Nimble", SNE = "Sneak",
    BAA = "Axe", BUA = "Blunt", CRP = "Woodwork", COO = "Cooking",
    FRM = "Farming", DOC = "Doctor", ELC = "Electricity", MTL = "MetalWelding",
    FKN = "FlintKnapping", CRV = "Carving", AIM = "Aiming", REL = "Reloading",
    FIS = "Fishing", TRA = "Trapping", FOR = "PlantScavenging", TAI = "Tailoring",
    MEC = "Mechanics", CMB = "Combat", SPE = "Spear", SBU = "SmallBlunt",
    LBA = "LongBlade", SBA = "SmallBlade", MAS = "Masonry", POT = "Pottery",
    BLA = "Blacksmith", GLA = "Glassmaking", HUS = "Husbandry", BUT = "Butchering",
    TRK = "Tracking",
}

local function skillDisplayName(_skill)
    if not _skill or _skill == "" then return nil end
    local ok, name = pcall(function()
        local perk = nil
        if SkillBook and SkillBook[_skill] then perk = SkillBook[_skill].perk end
        if perk == nil then perk = Perks.FromString(_skill) end
        if perk == nil then return nil end
        return PerkFactory.getPerk(perk):getName()
    end)
    if ok and name and name ~= "" then return name end
    return _skill
end

-- ---------------------------------------------------------------------------
-- recordings (VHS / CDs)
-- ---------------------------------------------------------------------------

local function mediaTitle(_mediaData)
    local title = nil
    pcall(function()
        if _mediaData:hasTitle() then
            title = _mediaData:getTranslatedTitle()
            if _mediaData:hasSubTitle() and _mediaData:getSubtitleEN() ~= "Home VHS" then
                title = title .. " " .. _mediaData:getTranslatedSubTitle()
            end
        elseif _mediaData:hasSubTitle() then
            title = _mediaData:getTranslatedSubTitle()
        else
            title = _mediaData:getTranslatedItemDisplayName()
        end
    end)
    if title == nil or title == "" then return "?" end
    return title
end

-- Returns the skills a recording teaches and whether it teaches any recipe.
local function mediaTeaches(_mediaData)
    local skills = {}
    local seen = {}
    local recipes = false

    pcall(function()
        for i = 1, _mediaData:getLineCount() do
            local line = _mediaData:getLine(i - 1)
            local codes = line ~= nil and line:getCodes() or nil
            if codes ~= nil and codes ~= "" then
                for token in string.gmatch(tostring(codes), "[^,]+") do
                    if string.sub(token, 1, 4) == "RCP=" then
                        recipes = true
                    else
                        local perk = MEDIA_SKILL_CODES[string.sub(token, 1, 3)]
                        if perk ~= nil and not seen[perk] then
                            seen[perk] = true
                            table.insert(skills, skillDisplayName(perk))
                        end
                    end
                end
            end
        end
    end)

    return skills, recipes
end

local function buildMedia(_catalog, _order, _textures)
    local ok, err = pcall(function()
        local radio = getZomboidRadio()
        if radio == nil then return end
        local recorded = radio:getRecordedMedia()
        if recorded == nil then return end

        local categories = recorded:getCategories()
        for i = 1, categories:size() do
            local category = tostring(categories:get(i - 1))
            local list = recorded:getAllMediaForCategory(categories:get(i - 1))
            if list ~= nil then
                for j = 1, list:size() do
                    local mediaData = list:get(j - 1)
                    local skills, recipes = mediaTeaches(mediaData)
                    if #skills > 0 or recipes or not BAH.ONLY_EDUCATIONAL_MEDIA then
                        local entry = {
                            key = MEDIA_PREFIX .. tostring(mediaData:getId()),
                            kind = "media",
                            name = mediaTitle(mediaData),
                            category = category,
                            skills = skills,
                            teachesRecipes = recipes,
                            texture = _textures[category],
                            sortGroup = 3,
                        }
                        _catalog[entry.key] = entry
                        table.insert(_order, entry)
                    end
                end
            end
        end
    end)
    if not ok then
        BAH.log("could not read the recording list: " .. tostring(err))
    end
end

-- ---------------------------------------------------------------------------
-- build
-- ---------------------------------------------------------------------------

local function build()
    catalog = {}
    order = {}

    local mediaTextures = {}
    local allItems = getScriptManager():getAllItems()

    for i = 1, allItems:size() do
        local item = allItems:get(i - 1)
        if not item:getObsolete() and not item:isHidden() then
            -- remember one icon per recording category (VHS box, CD case, ...)
            local mediaCat = item:getRecordedMediaCat()
            if mediaCat ~= nil and mediaTextures[tostring(mediaCat)] == nil then
                pcall(function() mediaTextures[tostring(mediaCat)] = item:getNormalTexture() end)
            end

            if item:isItemType(ItemType.LITERATURE) then
                local skill = item:getSkillTrained()
                local recipes = item:getLearnedRecipes()
                local isBook = skill ~= nil and skill ~= ""
                local isMagazine = (not isBook) and recipes ~= nil and recipes:size() > 0

                if isBook or isMagazine then
                    local entry = {
                        key = item:getFullName(),
                        fullType = item:getFullName(),
                        kind = isMagazine and "magazine" or "book",
                        name = item:getDisplayName(),
                        isMagazine = isMagazine,
                        skill = isBook and skill or nil,
                        skillName = isBook and skillDisplayName(skill) or nil,
                        level = isBook and item:getLevelSkillTrained() or nil,
                        maxLevel = isBook and item:getMaxLevelTrained() or nil,
                        recipeCount = (recipes ~= nil) and recipes:size() or 0,
                        texture = nil,
                        sortGroup = isMagazine and 2 or 1,
                    }
                    -- Textures only exist on a client; a dedicated server keeps nil.
                    pcall(function() entry.texture = item:getNormalTexture() end)
                    catalog[entry.key] = entry
                    table.insert(order, entry)
                end
            end
        end
    end

    buildMedia(catalog, order, mediaTextures)

    table.sort(order, function(a, b)
        if a.sortGroup ~= b.sortGroup then return a.sortGroup < b.sortGroup end
        if a.sortGroup == 1 then
            local an = a.skillName or ""
            local bn = b.skillName or ""
            if an ~= bn then return an < bn end
            local al = a.level or 0
            local bl = b.level or 0
            if al ~= bl then return al < bl end
        elseif a.sortGroup == 3 then
            local ac = a.category or ""
            local bc = b.category or ""
            if ac ~= bc then return ac < bc end
        end
        return (a.name or "") < (b.name or "")
    end)

    local books, magazines, media = 0, 0, 0
    for _, entry in ipairs(order) do
        if entry.kind == "book" then books = books + 1
        elseif entry.kind == "magazine" then magazines = magazines + 1
        else media = media + 1 end
    end
    BAH.log("catalog built: " .. books .. " skill books, " .. magazines
            .. " magazines, " .. media .. " recordings")
end

-- key -> entry, built on first use (item scripts are loaded by then)
function BAH.getCatalog()
    if catalog == nil then build() end
    return catalog
end

-- display-ordered array: skill books by skill/level, then magazines, then recordings
function BAH.getCatalogOrder()
    if order == nil then build() end
    return order
end

function BAH.getCatalogEntry(_key)
    if type(_key) ~= "string" then return nil end
    return BAH.getCatalog()[_key]
end

function BAH.isTrackable(_key)
    if BAH.getCatalogEntry(_key) ~= nil then return true end
    -- A server that cannot read the recording list must still accept marks for it,
    -- otherwise clients silently fail to mark tapes; the id shape is all we can check.
    return type(_key) == "string"
            and string.sub(_key, 1, string.len(MEDIA_PREFIX)) == MEDIA_PREFIX
            and string.len(_key) > string.len(MEDIA_PREFIX)
end

-- The tracking key for an item the player is holding, or nil when it isn't tracked.
function BAH.keyForItem(_item)
    if _item == nil then return nil end

    if _item:IsLiterature() then
        local fullType = _item:getFullType()
        if BAH.getCatalogEntry(fullType) ~= nil then return fullType end
        return nil
    end

    if _item:isRecordedMedia() then
        local ok, mediaKey = pcall(function()
            local mediaData = _item:getMediaData()
            if mediaData == nil then return nil end
            return MEDIA_PREFIX .. tostring(mediaData:getId())
        end)
        if ok and mediaKey ~= nil and BAH.getCatalogEntry(mediaKey) ~= nil then
            return mediaKey
        end
    end

    return nil
end

-- Human-readable "what does this teach" line used by the UI.
function BAH.catalogSubtitle(_entry)
    if _entry == nil then return "" end

    if _entry.kind == "media" then
        local line = _entry.category or "VHS"
        if _entry.skills ~= nil and #_entry.skills > 0 then
            line = line .. " - " .. table.concat(_entry.skills, ", ")
        elseif _entry.teachesRecipes then
            line = line .. " - " .. getText("UI_BooksAtHome_TeachesRecipes", "?")
        end
        return line
    end

    if _entry.kind == "magazine" then
        return getText("UI_BooksAtHome_TeachesRecipes", tostring(_entry.recipeCount or 0))
    end

    local skill = _entry.skillName or _entry.skill or "?"
    local from = _entry.level or 0
    local to = _entry.maxLevel or 0
    if to > 0 and to >= from then
        return skill .. " " .. from .. "-" .. to
    end
    return skill
end
