@echo off
start "TRMP Preview" /b powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Launch-Mod.ps1"
