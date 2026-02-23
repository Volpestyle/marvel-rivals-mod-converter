@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR_WIN=%~dp0"
set "SCRIPT_DIR_WIN=%SCRIPT_DIR_WIN:~0,-1%"

for /f "delims=" %%I in ('wsl wslpath "%SCRIPT_DIR_WIN%"') do set "SCRIPT_DIR_WSL=%%I"
if not defined SCRIPT_DIR_WSL (
  echo Error: failed to resolve WSL path for "%SCRIPT_DIR_WIN%".
  echo Make sure WSL is installed and available.
  exit /b 1
)

set "BASE_CMD=cd \"%SCRIPT_DIR_WSL%\" && ./convert_marvel_rivals_mod.sh"
set "ARGS="

:collect
if "%~1"=="" goto run
set "ONE=%~1"
set "ONE=%ONE:\=\\%"
set "ARGS=!ARGS! \"!ONE!\""
shift
goto collect

:run
wsl bash -lc "%BASE_CMD%%ARGS%"
exit /b %ERRORLEVEL%
