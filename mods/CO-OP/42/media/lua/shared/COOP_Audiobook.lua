--
-- CO-OP - audiobooks: skill books burned onto CDs at a powered desktop computer.
--
-- An audiobook is a vanilla Base.Disc_Retail carrying recorded media of the mod's own,
-- one per skill book, so it plays in everything a music CD plays in - a CD player, a
-- radio that takes discs, a car radio - and needs no item of its own. The one item the
-- mod adds is the blank disc (scripts/coop_audiobook.txt): vanilla has none.
--
-- At a computer (right-click, COOP_AudiobookUI) a blank disc and a skill book make the
-- audiobook, the book is kept; any CD, audiobook or not, can be wiped back to blank.
-- The computer has to have power, from the grid or a generator.
--
-- ---------------------------------------------------------------------------
-- Why listening is timed by the clock, not by the disc
-- ---------------------------------------------------------------------------
--
-- A device plays recorded media one line at a time, and how long a line lasts is fixed
-- in Java (DeviceData.updateMediaPlaying: the length of the line's text, clamped to
-- 90-300 ticks). No sandbox option touches it, so a disc can never be made to last
-- exactly as long as reading the book does. The disc is only the signal that the book
-- is being heard: every line fires OnDeviceText, and the game minutes between two lines
-- heard by the same player are what count (COOPAudiobookServer). The listening time a
-- book needs is the time reading it would take that same player - pages times the
-- MinutesPerPage sandbox option, with the reader traits, reading glasses and sitting
-- applied exactly as ISReadABook:getDuration applies them. A disc that runs out before
-- the book is done is simply played again; the count carries on.
--
-- What it gives is what reading gives: the minutes become pages read of that book, on
-- the same per-character counter the book's tooltip shows ("110 / 220"), and the XP
-- multiplier follows the pages the way ISReadABook.checkMultiplier has it - a tenth of
-- the volume's maximum for every tenth of the book. The volume has to suit the
-- listener's level, the same window reading uses; outside it nothing is counted.
--
-- ---------------------------------------------------------------------------
-- The recorded media
-- ---------------------------------------------------------------------------
--
-- One entry per vanilla skill book, registered on OnInitRecordedMedia on every machine
-- from the item scripts, sorted, so a server and its clients build the same list. The
-- category is "cds" in lower case: RecordedMedia.getMediaTypeForCategory matches it
-- without regard to case, so the media is a CD to every device, but the loot tables are
-- built from the "CDs" category alone, so audiobooks never spawn in the world.
--
-- Most lines are silent - RM_COOP_AB_Silence translates to an empty string - and every
-- CHAPTER_LINES-th line names a chapter, so a playing audiobook shows a line now and
-- then instead of a bubble every second. Every line carries a code, because
-- OnDeviceText is only fired for lines that have one; "CAB" is not a code vanilla's
-- ISRadioInteractions knows, so it ignores it.
--
-- The text keys are shared by every audiobook. That keeps the per-player list of known
-- media lines (saved with a 16-bit count) to a handful of entries however much is
-- listened to.
--

require "COOP_Common"

COOPAudiobook = COOPAudiobook or {}

COOPAudiobook.MODULE = "CO-OP"

-- commands on the mod channel
COOPAudiobook.CMD_BURN = "abBurn"          -- client -> server: burn a book onto a blank
COOPAudiobook.CMD_ERASE = "abErase"        -- client -> server: wipe a CD back to blank
COOPAudiobook.CMD_HEARD = "abHeard"        -- client -> server: a held player played a line
COOPAudiobook.CMD_RESULT = "abResult"      -- server -> client: how a burn or erase went
COOPAudiobook.CMD_PAGES = "abPages"        -- server -> client: pages heard of a book

COOPAudiobook.BLANK = "COOP.BlankCD"
COOPAudiobook.DISC = "Base.Disc_Retail"

COOPAudiobook.MEDIA_PREFIX = "coopab-"     -- media ids stay under 36 characters
COOPAudiobook.CATEGORY = "cds"

-- How long the disc runs, in lines per page of the book, and how often a chapter is
-- named. At the 90-tick minimum a line lasts a little over a second, so a first volume
-- (220 pages) plays for about a quarter of an hour at normal speed.
COOPAudiobook.LINES_PER_PAGE = 3
COOPAudiobook.CHAPTER_LINES = 60
COOPAudiobook.CODES = "CAB+0"

-- Game minutes at the computer.
COOPAudiobook.BURN_MINUTES = 60
COOPAudiobook.ERASE_MINUTES = 15

-- How far from the computer the player may stand, in tiles; the server allows one more.
COOPAudiobook.REACH = 2

-- The longest gap between two lines that still counts as listening, in game minutes.
-- A line never lasts this long; a longer gap means the disc was stopped, and only the
-- next line starts the count again.
COOPAudiobook.MAX_GAP_MINUTES = 5

-- How far a world device is heard, the same box vanilla's ISRadioInteractions uses.
COOPAudiobook.HEAR_RANGE = 5

COOPAudiobook.COMPUTER_SPRITES = {
    appliances_com_01_72 = true,
    appliances_com_01_73 = true,
    appliances_com_01_74 = true,
    appliances_com_01_75 = true,
}

-- the volume's first trained level -> which of SkillBook's maxMultiplierN it uses
local VOLUME_BY_LEVEL = { [1] = 1, [3] = 2, [5] = 3, [7] = 4, [9] = 5 }

function COOPAudiobook.isEnabled()
    return COOP.featureEnabled(COOP.F_AUDIOBOOKS)
end

-- ---------------------------------------------------------------------------
-- the books
-- ---------------------------------------------------------------------------

local books = nil           -- media id -> book
local bookByType = nil      -- "Base.BookCarpentry1" -> book
local bookList = nil        -- sorted by full type

local function buildBooks()
    books, bookByType, bookList = {}, {}, {}

    -- Read from the item scripts alone. SkillBook (server/XpSystem) is only needed for
    -- the perk and the multipliers, which are the server's; the list itself has to come
    -- out the same on every machine, because it decides which media get registered.
    local ok, err = pcall(function()
        local items = getScriptManager():getAllItems()
        for i = 0, items:size() - 1 do
            local script = items:get(i)
            local skill = script:getSkillTrained()
            local pages = script:getNumberOfPages()
            local level = script:getLevelSkillTrained()
            local volume = VOLUME_BY_LEVEL[level]
            if skill ~= nil and skill ~= "" and pages ~= nil and pages > 0 and volume ~= nil then
                local fullType = script:getFullName()
                local shortType = script:getName()
                local book = {
                    fullType = fullType,
                    skill = skill,
                    pages = pages,
                    minLevel = level,
                    -- Literature.getMaxLevelTrained, not the script's: the item reads
                    -- LvlSkillTrained + NumLevelsTrained - 1
                    maxLevel = level + script:getNumLevelsTrained() - 1,
                    volume = volume,
                    mediaId = COOPAudiobook.MEDIA_PREFIX .. shortType,
                    nameKey = "RM_COOP_AB_" .. shortType,
                }
                table.insert(bookList, book)
            end
        end
    end)
    if not ok then
        COOP.log("audiobooks: could not read the skill books: " .. tostring(err))
    end

    table.sort(bookList, function(a, b) return a.fullType < b.fullType end)
    for _, book in ipairs(bookList) do
        books[book.mediaId] = book
        bookByType[book.fullType] = book
    end
end

function COOPAudiobook.getBooks()
    if bookList == nil then buildBooks() end
    return bookList
end

function COOPAudiobook.bookForMediaId(_id)
    if books == nil then buildBooks() end
    if _id == nil then return nil end
    return books[_id]
end

function COOPAudiobook.bookForType(_fullType)
    if bookByType == nil then buildBooks() end
    if _fullType == nil then return nil end
    return bookByType[_fullType]
end

function COOPAudiobook.bookForItem(_item)
    if _item == nil then return nil end
    return COOPAudiobook.bookForType(_item:getFullType())
end

function COOPAudiobook.perk(_book)
    local entry = _book and SkillBook and SkillBook[_book.skill]
    return entry and entry.perk or nil
end

function COOPAudiobook.maxMultiplier(_book)
    local entry = _book and SkillBook and SkillBook[_book.skill]
    if entry == nil then return 1 end
    return entry["maxMultiplier" .. tostring(_book.volume)] or 1
end

-- The reading window of ISReadABook: a volume is for the two levels it trains.
function COOPAudiobook.levelSuits(_player, _book)
    local perk = COOPAudiobook.perk(_book)
    if perk == nil then return false end
    local level = _player:getPerkLevel(perk)
    return _book.minLevel <= level + 1 and _book.maxLevel >= level + 1
end

-- The book an item is an audiobook of, or nil for a music CD, a blank or anything else.
function COOPAudiobook.bookForDisc(_item)
    if _item == nil or _item:getFullType() ~= COOPAudiobook.DISC then return nil end
    local ok, media = pcall(function() return _item:getMediaData() end)
    if not ok or media == nil then return nil end
    return COOPAudiobook.bookForMediaId(media:getId())
end

function COOPAudiobook.mediaFor(_book)
    if _book == nil then return nil end
    local ok, media = pcall(function()
        return getZomboidRadio():getRecordedMedia():getMediaData(_book.mediaId)
    end)
    if ok then return media end
    return nil
end

-- ---------------------------------------------------------------------------
-- how long it takes
-- ---------------------------------------------------------------------------

function COOPAudiobook.minutesPerPageOption()
    local value = nil
    pcall(function()
        value = getSandboxOptions():getOptionByName("MinutesPerPage"):getValue()
    end)
    value = tonumber(value)
    if value == nil or value < 0 then value = 2.0 end
    return value
end

-- Game minutes one page takes this player, by ISReadABook:getDuration's modifiers.
function COOPAudiobook.minutesPerPage(_player)
    local minutes = COOPAudiobook.minutesPerPageOption()
    pcall(function()
        if _player:hasTrait(CharacterTrait.FAST_READER) then minutes = minutes * 0.7 end
        if _player:hasTrait(CharacterTrait.SLOW_READER) then minutes = minutes * 1.3 end
    end)
    pcall(function()
        local eyes = _player:getWornItems():getItem(ItemBodyLocation.EYES)
        if eyes ~= nil and eyes:getType() == "Glasses_Reading" then minutes = minutes * 0.9 end
    end)
    pcall(function()
        if _player:isSitting() then minutes = minutes * 0.9 end
    end)
    return minutes
end

-- Timed-action ticks for a number of game minutes. ISReadABook takes
-- pages * MinutesPerPage * minutesPerDay * 2 ticks for pages * MinutesPerPage minutes.
function COOPAudiobook.ticksFor(_minutes)
    return _minutes * getGameTime():getMinutesPerDay() * 2
end

-- The multiplier the pages read are worth, as ISReadABook.checkMultiplier works it out.
function COOPAudiobook.multiplierFor(_book, _pages)
    local percent = math.min(100, (_pages / _book.pages) * 100)
    return math.floor(percent / 10) * (COOPAudiobook.maxMultiplier(_book) / 10)
end

-- ---------------------------------------------------------------------------
-- the computer
-- ---------------------------------------------------------------------------

function COOPAudiobook.isComputer(_object)
    if _object == nil then return false end
    local ok, result = pcall(function()
        local sprite = _object:getSprite()
        local name = sprite and sprite:getName()
        if name ~= nil and COOPAudiobook.COMPUTER_SPRITES[name] then return true end
        local props = _object:getProperties()
        return props ~= nil and props:get("CustomName") == "Computer"
                and props:get("GroupName") == "Desktop"
    end)
    return ok and result == true
end

function COOPAudiobook.findComputer(_square)
    if _square == nil then return nil end
    local objects = _square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if COOPAudiobook.isComputer(object) then return object end
    end
    return nil
end

-- Grid power (before the shutoff, in a room) or a generator's reach. checkObjectPowered
-- is the engine's own test for appliances; the fallback is the same test spelled out the
-- way vanilla's car battery charger menu does it.
function COOPAudiobook.isPowered(_object)
    if _object == nil then return false end
    local ok, powered = pcall(function() return _object:checkObjectPowered() end)
    if ok and powered ~= nil then return powered == true end

    local square = _object:getSquare()
    if square == nil then return false end
    local okSq, result = pcall(function()
        return square:haveElectricity() or (square:hasGridPower() and square:getRoom() ~= nil)
    end)
    return okSq and result == true
end

-- ---------------------------------------------------------------------------
-- what can go in
-- ---------------------------------------------------------------------------

-- Any CD at all can be wiped: a music CD, an audiobook, or one with nothing on it.
function COOPAudiobook.isErasable(_item)
    return _item ~= nil and _item:getFullType() == COOPAudiobook.DISC
end

function COOPAudiobook.isBlank(_item)
    return _item ~= nil and _item:getFullType() == COOPAudiobook.BLANK
end

-- Items the player carries, in the main inventory and the bags in it.
function COOPAudiobook.collect(_player, _predicate)
    local found = {}
    local ok, list = pcall(function()
        return _player:getInventory():getAllEvalRecurse(function(item) return _predicate(item) end)
    end)
    if ok and list ~= nil then
        for i = 0, list:size() - 1 do table.insert(found, list:get(i)) end
    end
    return found
end

-- ---------------------------------------------------------------------------
-- registering the media
-- ---------------------------------------------------------------------------

local SILENCE = "RM_COOP_AB_Silence"
local AUTHOR = "RM_COOP_AB_Author"

function COOPAudiobook.registerMedia(_rc)
    if _rc == nil then return end
    local count = 0
    for _, book in ipairs(COOPAudiobook.getBooks()) do
        local ok, err = pcall(function()
            local data = _rc:register(COOPAudiobook.CATEGORY, book.mediaId, book.nameKey, 0)
            if data == nil then return end      -- the id was there already
            data:setTitle(book.nameKey)
            data:setAuthor(AUTHOR)

            local lines = book.pages * COOPAudiobook.LINES_PER_PAGE
            for i = 0, lines - 1 do
                if i % COOPAudiobook.CHAPTER_LINES == 0 then
                    local chapter = math.floor(i / COOPAudiobook.CHAPTER_LINES) + 1
                    data:addLine("RM_COOP_AB_Chapter" .. chapter, 0.85, 0.80, 0.60, COOPAudiobook.CODES)
                elseif i == lines - 1 then
                    data:addLine("RM_COOP_AB_End", 0.85, 0.80, 0.60, COOPAudiobook.CODES)
                else
                    data:addLine(SILENCE, 1.0, 1.0, 1.0, COOPAudiobook.CODES)
                end
            end
            count = count + 1
        end)
        if not ok then
            COOP.log("audiobooks: could not register " .. tostring(book.mediaId) .. ": " .. tostring(err))
        end
    end
    COOP.log("audiobooks: " .. count .. " registered")
end

Events.OnInitRecordedMedia.Add(COOPAudiobook.registerMedia)
