@echo off
powershell.exe -NoProfile -File "%~dp0Stop_MCUViewer_DAP.ps1"
if errorlevel 1 pause
