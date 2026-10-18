--
-- CO-OP - the boombox: music from YouTube that everyone around its holder hears.
--
-- ---------------------------------------------------------------------------
-- Why there is a program outside the game
-- ---------------------------------------------------------------------------
--
-- The game cannot do this alone. Lua here has no network access at all, and FMOD only
-- plays files that were in a mod's media folder when the game started:
-- FMODManager.loadSound resolves the name through ZomboidFileSystem.activeFileMap, which
-- is built once at load, so a file downloaded later can never be played by the engine.
--
-- So every player who wants to hear the music runs a small companion program, the
-- Boombox speaker (boombox/CoopBoombox.cmd in the repository). It plays the audio with
-- mpv, which streams YouTube through yt-dlp. The game and the speaker talk through two
-- text files in Zomboid/Lua/, the one folder Lua may write to (getFileWriter):
--
--   coop_boombox.txt          game -> speaker, rewritten a few times a second: every
--                             boombox this client can hear, how loud, and where in the
--                             track it is. An empty list, or a file that stops being
--                             rewritten (game closed, paused, back at the main menu),
--                             means silence.
--   coop_boombox_speaker.txt  speaker -> game, about once a second: that it is running,
--                             and the title and length of what it plays.
--
-- Without the speaker the boombox still works for everyone else - the server runs it,
-- the speaker only makes it audible on that one PC - and the window says it is missing.
--
-- ---------------------------------------------------------------------------
-- Who decides what
-- ---------------------------------------------------------------------------
--
-- The server owns every boombox that is playing (COOP_BoomboxServer): which link, the
-- volume, paused or not, and the position, kept as "this many seconds in at this
-- moment" so it is the same for everyone. Only the player holding the boombox in their
-- hands can change it, and it stops the moment it leaves them. Each client works out
-- how loud the music is where its own player stands (COOPBoombox.loudness) and passes
-- that to its speaker.
--

require "COOP_Common"

COOPBoombox = COOPBoombox or {}

COOPBoombox.MODULE = "CO-OP"
COOPBoombox.ITEM = "COOP.Boombox"

-- commands on the mod channel
COOPBoombox.CMD_PLAY = "bbPlay"         -- client -> server: { item, url }
COOPBoombox.CMD_STOP = "bbStop"         -- client -> server: { item }
COOPBoombox.CMD_PAUSE = "bbPause"       -- client -> server: { item, paused }
COOPBoombox.CMD_VOLUME = "bbVolume"     -- client -> server: { item, volume }
COOPBoombox.CMD_META = "bbMeta"         -- client -> server: { item, url, title, duration }
COOPBoombox.CMD_SYNC = "bbSync"         -- client -> server: send me every boombox
COOPBoombox.CMD_STATE = "bbState"       -- server -> clients: one boombox changed
COOPBoombox.CMD_GONE = "bbGone"         -- server -> clients: one boombox went quiet
COOPBoombox.CMD_ALL = "bbAll"           -- server -> client: every boombox, on CMD_SYNC
COOPBoombox.CMD_RESULT = "bbResult"     -- server -> client: why a command was refused

-- the files shared with the speaker, in Zomboid/Lua/
COOPBoombox.OUT_FILE = "coop_boombox.txt"
COOPBoombox.IN_FILE = "coop_boombox_speaker.txt"

COOPBoombox.DEFAULT_VOLUME = 0.6
COOPBoombox.VOLUME_STEPS = 10

COOPBoombox.URL_MAX = 200
COOPBoombox.TITLE_MAX = 120

function COOPBoombox.isEnabled()
    return COOP.featureEnabled(COOP.F_BOOMBOX)
end

-- How far the boombox carries at full volume, in tiles.
function COOPBoombox.maxRange()
    return COOP.numberOption("BoomboxRange", 20, 5, 60)
end

function COOPBoombox.attractsZombies()
    return COOP.option("BoomboxNoise", true) ~= false
end

function COOPBoombox.isBoombox(_item)
    return _item ~= nil and _item:getFullType() == COOPBoombox.ITEM
end

-- The boombox in the player's hands, either hand, or nil.
function COOPBoombox.heldBy(_player)
    if _player == nil then return nil end
    local primary = _player:getPrimaryHandItem()
    if COOPBoombox.isBoombox(primary) then return primary end
    local secondary = _player:getSecondaryHandItem()
    if COOPBoombox.isBoombox(secondary) then return secondary end
    return nil
end

function COOPBoombox.holds(_player, _itemId)
    local item = COOPBoombox.heldBy(_player)
    return item ~= nil and item:getID() == _itemId
end

-- The key a boombox's holder is stored under: the online id in multiplayer, the player
-- index in single player, where online ids are not handed out.
function COOPBoombox.playerKey(_player)
    if isClient() or isServer() then return _player:getOnlineID() end
    return _player:getPlayerNum()
end

function COOPBoombox.playerFor(_key)
    if _key == nil then return nil end
    if isClient() or isServer() then return getPlayerByOnlineID(_key) end
    return getSpecificPlayer(_key)
end

-- ---------------------------------------------------------------------------
-- links
-- ---------------------------------------------------------------------------

-- A link every speaker will accept, or nil. Only YouTube, only https, and only the
-- characters a YouTube link uses: the link goes from one player's text box to every
-- other player's PC, and the speaker hands it to mpv, so nothing else gets through.
-- The speaker checks it again on its side. A bare 11-character video id is taken too.
function COOPBoombox.cleanUrl(_text)
    if _text == nil then return nil end
    local url = tostring(_text):gsub("^%s+", ""):gsub("%s+$", "")
    if url == "" or #url > COOPBoombox.URL_MAX then return nil end

    if url:match("^[%w_%-]+$") and #url == 11 then
        return "https://www.youtube.com/watch?v=" .. url
    end

    url = url:gsub("^http://", "https://")
    if not url:match("^https://") then url = "https://" .. url end
    if url:find("[^%w%-%._~:/%?#=&%%]") then return nil end

    local host, rest = url:match("^https://([^/%?#]+)(.*)$")
    if host == nil then return nil end
    host = host:lower()
    local allowed = host == "youtube.com" or host == "www.youtube.com" or host == "m.youtube.com"
            or host == "music.youtube.com" or host == "youtu.be"
    if not allowed then return nil end
    -- in lower case, as the speaker's own check wants it
    return "https://" .. host .. rest
end

-- Free text from somebody else's PC, made safe to show and to write into a file line.
function COOPBoombox.cleanTitle(_text)
    if _text == nil then return nil end
    local title = tostring(_text):gsub("[%c|]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if title == "" then return nil end
    if #title > COOPBoombox.TITLE_MAX then title = title:sub(1, COOPBoombox.TITLE_MAX) end
    return title
end

function COOPBoombox.clampVolume(_value)
    local volume = tonumber(_value)
    if volume == nil or volume ~= volume then return COOPBoombox.DEFAULT_VOLUME end
    return math.max(0, math.min(1, volume))
end

-- ---------------------------------------------------------------------------
-- how loud it is where a listener stands
-- ---------------------------------------------------------------------------

-- 0..1. The holder hears it at the boombox's volume; further away it fades to nothing
-- at the edge of its reach, which grows with the volume (a quiet boombox is a quiet
-- boombox across the street, not a faint one). A floor between costs as much as six
-- tiles, a wall between indoors and out halves it, and a car's own cabin keeps it in.
function COOPBoombox.loudness(_box, _holder, _listener)
    if _box == nil or _holder == nil or _listener == nil then return 0 end
    local volume = COOPBoombox.clampVolume(_box.volume)
    if volume <= 0 then return 0 end
    if _holder == _listener then return volume end

    local reach = COOPBoombox.maxRange() * (0.3 + 0.7 * volume)
    local dx = _holder:getX() - _listener:getX()
    local dy = _holder:getY() - _listener:getY()
    local floors = math.abs(math.floor(_holder:getZ()) - math.floor(_listener:getZ()))
    local distance = math.sqrt(dx * dx + dy * dy) + floors * 6
    if distance >= reach then return 0 end

    local loud = volume * (1 - distance / reach)

    local vehicle, other = _holder:getVehicle(), _listener:getVehicle()
    if vehicle ~= other then
        if vehicle ~= nil or other ~= nil then loud = loud * 0.35 end
    else
        local a, b = _holder:getSquare(), _listener:getSquare()
        if vehicle == nil and a ~= nil and b ~= nil and a:isOutside() ~= b:isOutside() then
            loud = loud * 0.5
        end
    end
    return loud
end

-- Seconds into the track at the local clock _nowMs, for a box received at _box.recvMs.
function COOPBoombox.position(_box, _nowMs)
    if _box == nil then return 0 end
    local pos = tonumber(_box.pos) or 0
    if _box.paused or _box.recvMs == nil then return pos end
    return pos + math.max(0, (_nowMs - _box.recvMs) / 1000)
end

function COOPBoombox.formatTime(_seconds)
    local s = math.max(0, math.floor(tonumber(_seconds) or 0))
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    s = s % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

-- The recipe's sandbox switch, as COOPGlass.onTest: with the feature off no input
-- passes, so the boombox cannot be made.
function COOPBoombox.onTest(_item, _character)
    return COOPBoombox.isEnabled()
end
