@echo off
rem Runs install.ps1 with the execution policy bypassed (Windows blocks unsigned .ps1 files by default).
rem Usage: install.cmd -Agent claude [-Project]   or   install.cmd -Update
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
