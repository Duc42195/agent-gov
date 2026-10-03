@echo off
rem Runs install.ps1 with the execution policy bypassed (Windows blocks unsigned .ps1 files by default).
rem Usage: install.cmd -Agent claude [-Project] [-Uninstall]
rem In an interactive cmd.exe window CMDCMDLINE has no /c; started from PowerShell or Explorer it does.
echo "%CMDCMDLINE%" | find /i "/c" >nul
if errorlevel 1 set AGENT_GOV_SHELL=cmd
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
