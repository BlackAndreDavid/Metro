@echo off
setlocal
cd /d "%~dp0..\.."
python tools\editors\server.py
if errorlevel 1 pause
