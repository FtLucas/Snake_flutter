@echo off
setlocal ENABLEDELAYEDEXPANSION
REM Change to the directory of this script (Snake_flutter)
cd /d "%~dp0"

REM Prefer the repo's Flutter SDK sibling if available
set "FLUTTER_SDK=%~dp0..\flutter\bin\flutter.bat"
if exist "%FLUTTER_SDK%" (
	set "FLUTTER_CMD=%FLUTTER_SDK%"
	echo Using local Flutter SDK at %FLUTTER_SDK%
)
if not defined FLUTTER_CMD (
	set "FLUTTER_CMD=flutter"
	echo Using Flutter from PATH
)

call "%FLUTTER_CMD%" --no-version-check clean
if errorlevel 1 exit /b %errorlevel%
call "%FLUTTER_CMD%" --no-version-check pub get
exit /b %errorlevel%
