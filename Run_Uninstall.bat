@echo off
:: Shelby Edge Remove Script - UNINSTALL mode
:: Removes Edge without locking the folders. Run as Administrator.
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ShelbyEdgeRemove.ps1" -Mode Uninstall
pause
