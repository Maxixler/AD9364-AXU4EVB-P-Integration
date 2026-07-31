@echo off
setlocal
set "TOOLS_DIR=%~dp0"
set "APP_ELF=%TOOLS_DIR%..\..\vitis_ethernet\workspace\ad9364app\Release\ad9364app.elf"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TOOLS_DIR%Invoke-Axu4evAd9364Launch.ps1" -Mode Candidate -CandidateApplication "%APP_ELF%" %*
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" echo Ethernet development launch failed with exit code %RC%.
if "%RC%"=="0" echo Ethernet development ELF launched. Check PS_UART for PL_FFT_ETH: READY.
pause
exit /b %RC%
