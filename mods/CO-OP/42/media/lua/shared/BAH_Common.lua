--
-- CO-OP / Books at home - shared constants and helpers.
--

BAH = BAH or {}

BAH.MODULE = "BooksAtHome"          -- client/server command module
BAH.MODDATA_KEY = "BooksAtHome"     -- global mod data key (server-side storage)
BAH.SCHEMA = 1                      -- bump when the stored table layout changes
BAH.NOTE_MAX = 64                   -- max characters kept from a location note
BAH.WRITE_WINDOW_MS = 2000          -- rate limit window, per player
BAH.WRITE_LIMIT = 25                -- writes allowed inside that window

-- Only recordings that teach a skill or a recipe are tracked, matching the rule used
-- for books. Set to false to list every VHS and CD, music and movies included.
BAH.ONLY_EDUCATIONAL_MEDIA = true

function BAH.log(_msg)
    print("[BooksAtHome] " .. tostring(_msg))
end

-- true when there is no server at all (solo game): client and server code share one Lua state
function BAH.isSinglePlayer()
    return not isClient() and not isServer()
end

-- Strips line breaks and surrounding spaces, caps the length. Returns nil for an empty note.
function BAH.cleanNote(_note)
    if type(_note) ~= "string" then return nil end
    local note = _note:gsub("[\r\n\t]", " ")
    note = note:gsub("^%s+", "")
    note = note:gsub("%s+$", "")
    if note == "" then return nil end
    if string.len(note) > BAH.NOTE_MAX then
        note = string.sub(note, 1, BAH.NOTE_MAX)
    end
    return note
end

-- In-game calendar stamp, e.g. "12 Jul, 14:20". Safe to call from either side.
function BAH.gameDateString()
    local ok, stamp = pcall(function()
        local gt = getGameTime()
        return string.format("%02d/%02d/%d %02d:%02d",
                gt:getDay() + 1, gt:getMonth() + 1, gt:getYear(),
                gt:getHour(), gt:getMinutes())
    end)
    if ok and stamp then return stamp end
    return "?"
end

function BAH.worldAgeHours()
    local ok, hours = pcall(function() return getGameTime():getWorldAgeHours() end)
    if ok and hours then return hours end
    return 0
end

-- Best available name for a player: MP username, otherwise the character's forename.
function BAH.playerName(_playerObj)
    if _playerObj == nil then return "?" end
    local name = nil
    local okUser, user = pcall(function() return _playerObj:getUsername() end)
    if okUser and user and user ~= "" then name = tostring(user) end
    if name == nil then
        local okDesc, forename = pcall(function() return _playerObj:getDescriptor():getForename() end)
        if okDesc and forename and forename ~= "" then name = tostring(forename) end
    end
    return name or "?"
end
