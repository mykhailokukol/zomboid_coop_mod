@echo off
rem CO-OP Boombox speaker: double-click to hear the boombox in Project Zomboid.
rem Keep the window open while you play. See CoopBoombox.ps1 for what it does.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0CoopBoombox.ps1" %*
if errorlevel 1 pause
