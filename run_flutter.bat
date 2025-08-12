@echo off
cd /d "%~dp0"
call flutter clean
call flutter pub get
exit /b 0
