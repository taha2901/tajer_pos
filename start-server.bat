@echo off
chcp 65001 >nul
title Tajer POS Server
cd /d "%~dp0backend"

echo ================================================
echo              Tajer POS - Local Server
echo ================================================

rem --- MongoDB: start the Windows service if it is stopped ---
sc query MongoDB | find "RUNNING" >nul
if errorlevel 1 (
  echo Starting MongoDB...
  net start MongoDB >nul 2>&1
  if errorlevel 1 (
    echo [!] Could not start MongoDB. Run this file as Administrator once.
  )
)

rem --- Firewall: allow phones on the Wi-Fi to reach port 3000 (needs admin, once) ---
netsh advfirewall firewall show rule name="Tajer POS Server" >nul 2>&1
if errorlevel 1 (
  netsh advfirewall firewall add rule name="Tajer POS Server" dir=in action=allow protocol=TCP localport=3000 profile=any >nul 2>&1
  if errorlevel 1 (
    echo [!] Firewall rule not added. Right-click this file ^> Run as administrator ^(first time only^).
  ) else (
    echo Firewall rule added for port 3000.
  )
)

if not exist node_modules (
  echo Installing packages...
  call npm install
)

echo.
echo  On your phone ^(same Wi-Fi^), open the app ^> server icon ^> enter:
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -ne 'WellKnown' }).IPAddress"`) do (
  echo     http://%%i:3000/api
)
echo.
echo  Keep this window open. Close it to stop the server.
echo ================================================
echo.

call npm start
pause
