@echo off
REM ============================================================
REM  Double-click this to pull the latest code from GitHub.
REM  If the Rojo server + Studio are connected, the update
REM  appears in Studio automatically. Just press Play to test.
REM ============================================================
cd /d "%~dp0"
git pull
echo.
echo   Done. If Studio is connected to Rojo, it already updated.
echo.
pause
