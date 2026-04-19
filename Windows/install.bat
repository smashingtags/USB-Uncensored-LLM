@echo off
setlocal
title Eight.ly Stick - Setup

cls
echo.
echo   ========================================================
echo                   EIGHT.LY STICK - SETUP
echo   ========================================================
echo.
echo      Portable uncensored AI, GPU-accelerated, zero-install.
echo      This will auto-detect your hardware, download the right
echo      engine, and let you pick which AI models to install.
echo.
echo      Minimum:   8 GB free disk
echo      Heavy:    32 GB free disk  (full model catalog)
echo.
echo   --------------------------------------------------------
echo.
pause

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-core.ps1"
set RC=%ERRORLEVEL%

echo.
if %RC%==0 (
  echo   ========================================================
  echo      SETUP COMPLETE.  Double-click start.bat to launch.
  echo   ========================================================
) else (
  echo   ========================================================
  echo      Setup exited with errors ^(code %RC%^).  Scroll up.
  echo   ========================================================
)
echo.
pause
