@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0forest-stress.ps1" %*
