@echo off
setlocal
cd /d "%~dp0..\.."
python tools\editors\desktop.py
if errorlevel 1 pause
