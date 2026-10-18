@echo off
:: Shelby Edge Remove Script - UNBLOCK mode
:: Restores default Windows permissions on Edge folders. Run as Administrator.
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ShelbyEdgeRemove.ps1" -Mode Unblock
pause
