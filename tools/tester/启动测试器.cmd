@echo off
setlocal
cd /d "%~dp0..\.."
if exist tools\bin\MetroTester\MetroTester.exe (
 tools\bin\MetroTester\MetroTester.exe
) else if exist .venv-editor\Scripts\python.exe (
 .venv-editor\Scripts\python.exe tools\tester\desktop.py
) else if exist .venv\Scripts\python.exe (
 .venv\Scripts\python.exe tools\tester\desktop.py
) else (
 python tools\tester\desktop.py
)
if errorlevel 1 pause
