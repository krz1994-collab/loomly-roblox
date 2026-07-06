@echo off
REM ============================================================
REM  Double-click this to start the Rojo live-sync server.
REM  Leave the window OPEN while you work. Then in Studio:
REM     Rojo (top toolbar)  ->  Connect
REM  After that, every `git pull` shows up in Studio by itself.
REM ============================================================
cd /d "%~dp0"
if not exist rojo.exe (
  echo.
  echo   rojo.exe is not in this folder.
  echo   Put rojo.exe next to this file, then double-click again.
  echo.
  pause
  exit /b 1
)
echo.
echo   Starting Rojo server. LEAVE THIS WINDOW OPEN.
echo   Now go to Studio -^> Rojo -^> Connect.
echo.
rojo.exe serve
pause
