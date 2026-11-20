@echo off
setlocal
cd /d "%~dp0..\.."
if not exist .venv-editor\Scripts\python.exe py -3 -m venv .venv-editor
.venv-editor\Scripts\python.exe -m pip install -r tools\build\requirements.txt
if errorlevel 1 goto done
.venv-editor\Scripts\python.exe tools\build\build_tools.py
:done
pause
