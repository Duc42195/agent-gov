@echo off
rem Runs score.ps1 with the execution policy bypassed. Usage: score.cmd [PROJECT_DIR] [--agent NAME] [--model NAME] [--write]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0score.ps1" %*
