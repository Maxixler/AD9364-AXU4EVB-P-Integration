@echo off
setlocal
cd /d "%~dp0..\.."
python -m PROJECT.ethernet_fft.app --bind 192.168.1.100 --port 5005 --frames 0 %*
exit /b %ERRORLEVEL%
