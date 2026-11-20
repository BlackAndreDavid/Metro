@echo off
setlocal
cd /d "%~dp0..\.."
if exist tools\bin\MetroEditor\MetroEditor.exe (
 tools\bin\MetroEditor\MetroEditor.exe
) else if exist .venv-editor\Scripts\python.exe (
 .venv-editor\Scripts\python.exe tools\editors\desktop.py
) else if exist .venv\Scripts\python.exe (
 .venv\Scripts\python.exe tools\editors\desktop.py
) else (
 python tools\editors\desktop.py
)
if errorlevel 1 pause
