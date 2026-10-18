@echo off
:: Shelby Edge Remove Script - BLOCK mode
:: Locks Edge install folders to prevent reinstall. Run as Administrator.
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ShelbyEdgeRemove.ps1" -Mode Block
pause
