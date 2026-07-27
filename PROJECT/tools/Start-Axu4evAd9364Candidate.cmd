@echo off
setlocal
set "TOOLS_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TOOLS_DIR%Invoke-Axu4evAd9364Launch.ps1" -Mode Candidate -CandidateRoot "%TOOLS_DIR%..\..\PROJECT\candidates\axu4ev-ad9364\fft-single-shot-v1"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" echo Launch failed with exit code %RC%.
if "%RC%"=="0" echo Candidate launch completed. Check PS_UART in PuTTY.
pause
exit /b %RC%
