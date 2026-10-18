<#
CO-OP Boombox speaker.

Plays the music of the boombox in Project Zomboid (the CO-OP mod) on this PC. The game
cannot stream from the internet itself, so every player who wants to hear a boombox
runs this next to the game. It needs two free programs, which it offers to install
with winget the first time:

  mpv     plays the audio            (winget id shinchiro.mpv)
  yt-dlp  finds the audio on YouTube (winget id yt-dlp.yt-dlp)

How it works: a few times a second the game writes Zomboid\Lua\coop_boombox.txt, every
boombox this player can hear, how loud and how far into the track. This script runs one
hidden mpv per boombox, keeps its volume, pause and position in line over mpv's IPC
pipe, and writes back Zomboid\Lua\coop_boombox_speaker.txt: that it is running, and the
title and length of what it plays. When the game stops writing (closed, main menu) the
music stops.

Usage:  CoopBoombox.cmd                      (double-click)
        CoopBoombox.cmd -ZomboidDir D:\Zomboid
        CoopBoombox.cmd -Verbose                (shows what mpv says)
#>

[CmdletBinding()]
param(
    [string]$ZomboidDir = (Join-Path $env:USERPROFILE 'Zomboid'),
    [int]$MaxPlayers = 4
)

$ErrorActionPreference = 'Stop'
$Inv = [System.Globalization.CultureInfo]::InvariantCulture

$LuaDir = Join-Path $ZomboidDir 'Lua'
$GameFile = Join-Path $LuaDir 'coop_boombox.txt'
$SpeakerFile = Join-Path $LuaDir 'coop_boombox_speaker.txt'

$TICK_MS = 150
$STALE_MS = 3000          # the game stopped writing: everything stops
$LINGER_MS = 15000        # out of earshot: muted this long before mpv is closed
$QUERY_MS = 2000
$SEEK_MIN_GAP_MS = 8000
$DRIFT_S = 2.5
$CONNECT_MS = 20000

# Only YouTube, only https, only the characters a YouTube link has - the same rule the
# mod applies (COOPBoombox.cleanUrl). The link comes from another player's PC.
$UrlPattern = '^https://(www\.|m\.|music\.)?(youtube\.com|youtu\.be)/[A-Za-z0-9\-._~:/?#=&%]*$'

function Now-Ms { [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }
function Num([double]$x) { $x.ToString('0.###', $Inv) }
function Say([string]$text) { Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $text) }

# ---------------------------------------------------------------------------
# mpv and yt-dlp
# ---------------------------------------------------------------------------

function Find-Tool([string]$name) {
    $candidates = @(
        (Join-Path $PSScriptRoot "$name.exe"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\$name.exe"),
        (Join-Path $env:ProgramFiles "mpv\$name.exe"),
        (Join-Path $env:ProgramFiles "MPV Player\$name.exe")
    )
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
    $cmd = Get-Command "$name.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    $packages = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path $packages) {
        $found = Get-ChildItem $packages -Recurse -Filter "$name.exe" -ErrorAction SilentlyContinue |
                Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    return $null
}

function Install-Tools {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Write-Host 'winget is not available. Install mpv and yt-dlp yourself, or put mpv.exe and'
        Write-Host "yt-dlp.exe next to this script ($PSScriptRoot)."
        return
    }
    # Deno is the JavaScript runtime yt-dlp now wants for YouTube; it mostly works without
    foreach ($id in @('shinchiro.mpv', 'yt-dlp.yt-dlp', 'DenoLand.Deno')) {
        Write-Host "Installing $id ..."
        & winget install -e --id $id --accept-source-agreements --accept-package-agreements
    }
}

$Mpv = Find-Tool 'mpv'
$YtDlp = Find-Tool 'yt-dlp'
if (-not $Mpv -or -not $YtDlp) {
    Write-Host 'The boombox speaker needs mpv and yt-dlp, and they were not found.'
    $answer = Read-Host 'Install them now with winget? [Y/n]'
    if ($answer -eq '' -or $answer -match '^[Yy]') { Install-Tools }
    $Mpv = Find-Tool 'mpv'
    $YtDlp = Find-Tool 'yt-dlp'
}
if (-not $Mpv -or -not $YtDlp) {
    Write-Host ''
    Write-Host "mpv:    $(if ($Mpv) { $Mpv } else { 'NOT FOUND' })"
    Write-Host "yt-dlp: $(if ($YtDlp) { $YtDlp } else { 'NOT FOUND' })"
    Write-Host 'Install the missing one (or open a new window after winget finished) and run this again.'
    exit 1
}
if (-not (Test-Path $LuaDir)) {
    Write-Host "No Zomboid folder at $ZomboidDir. Run with -ZomboidDir <path to your Zomboid folder>."
    exit 1
}

# mpv finds yt-dlp on its PATH
$ChildPath = (Split-Path $YtDlp -Parent) + ';' + $env:PATH

# Every mpv goes into a job object that dies with this window, so closing the console
# with the X button does not leave music playing with nobody to stop it.
$Job = $null
try {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CoopBoomboxJob {
    [StructLayout(LayoutKind.Sequential)] struct BASIC { public long a; public long b; public uint LimitFlags; public UIntPtr c; public UIntPtr d; public uint e; public UIntPtr f; public uint g; public uint h; }
    [StructLayout(LayoutKind.Sequential)] struct IO { public ulong a, b, c, d, e, f; }
    [StructLayout(LayoutKind.Sequential)] struct EXT { public BASIC Basic; public IO Io; public UIntPtr p, q, r, s; }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr a, string n);
    [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr j, int c, ref EXT i, uint l);
    [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr j, IntPtr p);
    public static IntPtr Create() {
        IntPtr job = CreateJobObject(IntPtr.Zero, null);
        EXT info = new EXT();
        info.Basic.LimitFlags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        SetInformationJobObject(job, 9, ref info, (uint)Marshal.SizeOf(typeof(EXT)));
        return job;
    }
    public static bool Assign(IntPtr job, IntPtr process) { return AssignProcessToJobObject(job, process); }
}
'@
    $Job = [CoopBoomboxJob]::Create()
} catch {
    Say "Could not set up the job object ($($_.Exception.Message)); close this window with Ctrl+C so the music stops."
}

# ---------------------------------------------------------------------------
# one mpv per boombox
# ---------------------------------------------------------------------------

$Players = @{}     # boombox id -> player
$Done = @{}        # "id|url" -> $true: played to the end or failed, not started again
$Errors = @{}      # boombox id -> @{ Url; Text }
$Meta = @{}        # boombox id -> @{ Url; Title; Duration }

function Quote-Arg([string]$a) {
    if ($a -notmatch '[\s"]') { return $a }
    return '"' + ($a -replace '"', '\"') + '"'
}

function Start-Player($box, [double]$expected) {
    $pipeName = "coopboombox-$PID-$($box.Id)-$(Get-Random)"
    $mpvArgs = @(
        '--no-video', '--no-terminal', '--force-window=no', '--idle=no', '--keep-open=no',
        '--ytdl-format=bestaudio/best', '--ytdl-raw-options=no-playlist=',
        "--input-ipc-server=\\.\pipe\$pipeName",
        "--volume=$(Num ($box.Loud * 100))",
        "--start=+$(Num $expected)",
        "--pause=$(if ($box.Paused) { 'yes' } else { 'no' })",
        '--', $box.Url
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Mpv
    $psi.Arguments = ($mpvArgs | ForEach-Object { Quote-Arg $_ }) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables['PATH'] = $ChildPath
    $proc = [System.Diagnostics.Process]::Start($psi)
    if ($Job) { [void][CoopBoomboxJob]::Assign($Job, $proc.Handle) }

    $Players[$box.Id] = [pscustomobject]@{
        Id = $box.Id; Url = $box.Url; Proc = $proc; PipeName = $pipeName; StartedMs = (Now-Ms)
        Pipe = $null; Reader = $null; Writer = $null; ReadTask = $null
        Volume = [double]($box.Loud * 100); Paused = [bool]$box.Paused
        Loaded = $false; FileLoaded = $false; Title = $null; Duration = $null
        LastQueryMs = 0; LastSeekMs = 0; GoneSinceMs = 0; Expected = $expected; Ended = $false
    }
    Say "playing $($box.Url) (boombox $($box.Id))"
}

function Stop-Player($p, [string]$why) {
    if ($p.Writer) { try { $p.Writer.WriteLine('{"command":["quit"]}') } catch {} }
    try { if (-not $p.Proc.HasExited) { if (-not $p.Proc.WaitForExit(300)) { $p.Proc.Kill() } } } catch {}
    try { if ($p.Pipe) { $p.Pipe.Dispose() } } catch {}
    $Players.Remove($p.Id)
    if ($why) { Say "stopped boombox $($p.Id): $why" }
}

function Send-Mpv($p, [string]$json) {
    if (-not $p.Writer) { return }
    try { $p.Writer.WriteLine($json) } catch { $p.Ended = $true }
}

function Connect-Player($p) {
    if ($p.Pipe) { return }
    try {
        $pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', $p.PipeName,
                [System.IO.Pipes.PipeDirection]::InOut, [System.IO.Pipes.PipeOptions]::Asynchronous)
        $pipe.Connect(30)
        $p.Pipe = $pipe
        $enc = New-Object System.Text.UTF8Encoding($false)
        $p.Reader = New-Object System.IO.StreamReader($pipe, $enc)
        $p.Writer = New-Object System.IO.StreamWriter($pipe, $enc)
        $p.Writer.AutoFlush = $true
        # the properties are asked for from here on; until the track is open they answer an error
        $p.Loaded = $true
    } catch {
        if ((Now-Ms) - $p.StartedMs -gt $CONNECT_MS) { $p.Ended = $true }
    }
}

function Handle-Line($p, [string]$line, $box) {
    Write-Verbose "mpv $($p.Id)> $line"
    try { $msg = $line | ConvertFrom-Json } catch { return }
    $props = $msg.PSObject.Properties
    if ($props['request_id']) {
        if ($msg.error -ne 'success') { return }
        switch ([int]$msg.request_id) {
            1 { Check-Drift $p ([double]$msg.data) $box }
            2 { $p.Duration = [double]$msg.data }
            3 { $p.Title = ([string]$msg.data) -replace '[\|\r\n\t]', ' ' }
        }
        return
    }
    if ($props['event']) {
        switch ($msg.event) {
            # before this the title is the link itself: yt-dlp has not looked it up yet
            'file-loaded' { $p.FileLoaded = $true }
            'end-file' {
                # 'redirect' is a link resolved into another one, still loading
                $reason = if ($props['reason']) { [string]$msg.reason } else { 'eof' }
                if ($reason -eq 'redirect') { return }
                $p.Ended = $true
                if ($reason -eq 'error') {
                    $text = if ($props['file_error']) { [string]$msg.file_error } else { 'error' }
                    $Errors[$p.Id] = @{ Url = $p.Url; Text = ($text -replace '[\|\r\n\t]', ' ') }
                    Say "boombox $($p.Id) could not play $($p.Url): $text"
                }
            }
        }
    }
}

# Everyone hears the same moment of the track, give or take a couple of seconds: mpv
# drifts while it buffers, and a player who walked up late starts where the others are.
function Check-Drift($p, [double]$timePos, $box) {
    if ($box -eq $null -or $box.Paused -or -not $p.Duration) { return }
    $expected = Expected-Position $box
    if ([Math]::Abs($timePos - $expected) -lt $DRIFT_S) { return }
    if ($expected -ge $p.Duration - 1) { return }
    $now = Now-Ms
    if ($now - $p.LastSeekMs -lt $SEEK_MIN_GAP_MS) { return }
    $p.LastSeekMs = $now
    Send-Mpv $p ('{"command":["seek",' + (Num $expected) + ',"absolute"]}')
}

function Drain-Player($p, $box) {
    if (-not $p.Reader) { return }
    for ($i = 0; $i -lt 50; $i++) {
        if ($p.ReadTask -eq $null) { $p.ReadTask = $p.Reader.ReadLineAsync() }
        if (-not $p.ReadTask.IsCompleted) { return }
        $line = $null
        try { $line = $p.ReadTask.Result } catch { $p.Ended = $true; return }
        $p.ReadTask = $null
        if ($line -eq $null) { $p.Ended = $true; return }
        Handle-Line $p $line $box
    }
}

# ---------------------------------------------------------------------------
# the game's file
# ---------------------------------------------------------------------------

$State = $null

function Read-GameFile {
    if (-not (Test-Path $GameFile)) { return $null }
    $text = $null
    try {
        $fs = [System.IO.File]::Open($GameFile, 'Open', 'Read', 'ReadWrite, Delete')
        try { $text = (New-Object System.IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
    } catch { return $script:State }
    $lines = $text -split "`r?`n" | Where-Object { $_ -ne '' }
    # half-written: keep what we had
    if ($lines.Count -lt 3 -or $lines[0] -ne 'coop-boombox 1' -or $lines[-1] -ne 'end') { return $script:State }
    if ($lines[1] -notmatch '^time (\d+)$') { return $script:State }
    $time = [double]::Parse($matches[1], $Inv)
    $boxes = @{}
    foreach ($l in $lines) {
        if ($l -match '^box (\d+)\|([\d.]+)\|([\d.]+)\|([01])\|(.+)$') {
            # read the groups first: the next -match overwrites $matches
            $box = [pscustomobject]@{
                Id = $matches[1]
                Loud = [Math]::Max(0.0, [Math]::Min(1.0, [double]::Parse($matches[2], $Inv)))
                Pos = [double]::Parse($matches[3], $Inv)
                Paused = ($matches[4] -eq '1')
                Url = $matches[5]
            }
            if ($box.Url -cmatch $UrlPattern) { $boxes[$box.Id] = $box }
        }
    }
    return [pscustomobject]@{ Time = $time; Boxes = $boxes }
}

function Expected-Position($box) {
    if ($box.Paused -or $script:State -eq $null) { return $box.Pos }
    return $box.Pos + [Math]::Max(0, ((Now-Ms) - $script:State.Time) / 1000.0)
}

# ---------------------------------------------------------------------------
# what the game reads back
# ---------------------------------------------------------------------------

$LastStatusMs = 0

function Write-Status {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("alive $(Now-Ms)")
    foreach ($id in @($Meta.Keys)) {
        $m = $Meta[$id]
        $duration = if ($m.Duration) { Num $m.Duration } else { '0' }
        $lines.Add("meta $id|$duration|$($m.Url)|$($m.Title)")
    }
    foreach ($id in @($Errors.Keys)) {
        $e = $Errors[$id]
        $lines.Add("error $id|$($e.Url)|$($e.Text)")
    }
    $tmp = "$SpeakerFile.tmp"
    try {
        [System.IO.File]::WriteAllText($tmp, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
        if (Test-Path $SpeakerFile) { [System.IO.File]::Replace($tmp, $SpeakerFile, [NullString]::Value) }
        else { [System.IO.File]::Move($tmp, $SpeakerFile) }
    } catch {}   # the game is reading it this very moment: next second
}

# ---------------------------------------------------------------------------
# the loop
# ---------------------------------------------------------------------------

function Update-All {
    $now = Now-Ms
    $script:State = Read-GameFile
    $stale = ($script:State -eq $null) -or ($now - $script:State.Time -gt $STALE_MS)
    $wanted = if ($stale) { @{} } else { $script:State.Boxes }

    foreach ($p in @($Players.Values)) {
        $box = $wanted[$p.Id]
        if ($stale) { Stop-Player $p 'the game stopped'; continue }
        if ($box -ne $null -and $box.Url -ne $p.Url) { Stop-Player $p 'new track'; continue }
        if ($p.Proc.HasExited) { $p.Ended = $true }

        Connect-Player $p
        Drain-Player $p $box

        if ($p.Ended) {
            $Done["$($p.Id)|$($p.Url)"] = $true
            Stop-Player $p 'track over'
            continue
        }

        if ($box -eq $null) {
            # out of earshot: muted for a while, so walking back in does not reload
            if ($p.GoneSinceMs -eq 0) { $p.GoneSinceMs = $now }
            if ($now - $p.GoneSinceMs -gt $LINGER_MS) { Stop-Player $p 'out of earshot'; continue }
            if ($p.Volume -ne 0) { $p.Volume = 0; Send-Mpv $p '{"command":["set_property","volume",0]}' }
            continue
        }
        $p.GoneSinceMs = 0

        $volume = [Math]::Round($box.Loud * 100, 1)
        if ([Math]::Abs($volume - $p.Volume) -ge 0.5) {
            $p.Volume = $volume
            Send-Mpv $p ('{"command":["set_property","volume",' + (Num $volume) + ']}')
        }
        if ($box.Paused -ne $p.Paused) {
            $p.Paused = $box.Paused
            Send-Mpv $p ('{"command":["set_property","pause",' + $(if ($box.Paused) { 'true' } else { 'false' }) + ']}')
            if (-not $box.Paused) {
                Send-Mpv $p ('{"command":["seek",' + (Num (Expected-Position $box)) + ',"absolute"]}')
            }
        }
        if ($p.Loaded -and $now - $p.LastQueryMs -ge $QUERY_MS) {
            $p.LastQueryMs = $now
            Send-Mpv $p '{"command":["get_property","time-pos"],"request_id":1}'
            if ($p.FileLoaded -and -not $p.Duration) { Send-Mpv $p '{"command":["get_property","duration"],"request_id":2}' }
            if ($p.FileLoaded -and -not $p.Title) { Send-Mpv $p '{"command":["get_property","media-title"],"request_id":3}' }
        }
        if ($p.Title) {
            $Meta[$p.Id] = @{ Url = $p.Url; Title = $p.Title; Duration = $p.Duration }
        }
    }

    # forget what belongs to boomboxes that are gone
    foreach ($key in @($Done.Keys)) {
        $id = $key.Split('|')[0]
        $box = $wanted[$id]
        if ($box -eq $null -or "$id|$($box.Url)" -ne $key) { $Done.Remove($key) }
    }
    foreach ($id in @($Meta.Keys)) { if ($wanted[$id] -eq $null -and -not $Players[$id]) { $Meta.Remove($id) } }
    foreach ($id in @($Errors.Keys)) { if ($wanted[$id] -eq $null) { $Errors.Remove($id) } }

    foreach ($box in $wanted.Values) {
        if ($Players[$box.Id] -ne $null) { continue }
        if ($Done["$($box.Id)|$($box.Url)"]) { continue }
        if ($Players.Count -ge $MaxPlayers) { break }
        Start-Player $box (Expected-Position $box)
    }

    if ($now - $script:LastStatusMs -ge 1000) {
        $script:LastStatusMs = $now
        Write-Status
    }
}

$Host.UI.RawUI.WindowTitle = 'CO-OP Boombox speaker'
Write-Host 'CO-OP Boombox speaker is running. Keep this window open while you play.'
Write-Host "  game folder: $ZomboidDir"
Write-Host "  mpv:         $Mpv"
Write-Host "  yt-dlp:      $YtDlp"
Write-Host 'Close the window or press Ctrl+C to stop.'
Write-Host ''

try {
    while ($true) {
        try { Update-All } catch { Say "error: $($_.Exception.Message)" }
        Start-Sleep -Milliseconds $TICK_MS
    }
} finally {
    foreach ($p in @($Players.Values)) { Stop-Player $p $null }
    try { Remove-Item $SpeakerFile -ErrorAction SilentlyContinue } catch {}
}
