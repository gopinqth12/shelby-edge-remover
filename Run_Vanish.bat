@echo off
:: Shelby Edge Remove Script - VANISH mode
:: Full removal + reinstall block. Run as Administrator.
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ShelbyEdgeRemove.ps1" -Mode Vanish
pause
