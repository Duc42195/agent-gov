@echo off
rem Runs plan.ps1 with the execution policy bypassed. Usage: plan.cmd list [--owner NAME] [--status STATUS]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0plan.ps1" %*
