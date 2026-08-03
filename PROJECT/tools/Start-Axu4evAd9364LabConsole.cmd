@echo off
setlocal
set "TOOLS_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TOOLS_DIR%Invoke-Axu4evAd9364Launch.ps1" -Mode Candidate -CandidateRoot "%TOOLS_DIR%..\..\PROJECT\candidates\axu4ev-ad9364\monopulse-live-lab-v2" %*
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" echo Launch failed with exit code %RC%.
if "%RC%"=="0" echo Lab UART Candidate launched. Start the Python lab console on PS_UART.
pause
exit /b %RC%
