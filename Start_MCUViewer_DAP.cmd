@echo off
powershell.exe -NoProfile -File "%~dp0Start_MCUViewer_DAP.ps1"
if errorlevel 1 pause
