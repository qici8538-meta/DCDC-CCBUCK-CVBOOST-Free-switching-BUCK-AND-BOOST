@echo off
echo Keep power-stage inputs OFF. Keep MCU and SLAVE DAP powered ON.
powershell.exe -NoProfile -File "%~dp0Stop_MCUViewer_DAP.ps1"
if errorlevel 1 goto failed
powershell.exe -NoProfile -File "%~dp0Start_MCUViewer_DAP.ps1"
if errorlevel 1 goto failed
echo In MCUViewer: STOP, click Connected to disconnect, then START.
exit /b 0
:failed
echo Reconnect failed. Check MCU/SLAVE power and wireless pairing.
pause
exit /b 1
