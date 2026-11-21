@echo off
setlocal
cd /d "%~dp0"
set COLLECTION=-collection:app=src
set VET=-vet -strict-style -warnings-as-errors
set OUT=build
if not exist %OUT% mkdir %OUT%

if "%1"=="setup" goto setup
if "%1"=="check" goto check
if "%1"=="fmt" goto fmt
if "%1"=="debug" goto debug
if "%1"=="release" goto release
if "%1"=="run" goto run
if "%1"=="test" goto test
if "%1"=="ci" goto ci
echo usage: build.bat {setup^|check^|fmt^|debug^|release^|run^|test^|ci}
echo Not available on Windows (use build.sh via WSL/Git Bash): fmt-check, test-golden, bench, worktree, worktree-remove.
exit /b 2

:setup
git config core.hooksPath .githooks || exit /b 1
echo hooks activated
git submodule update --init || echo WARN: could not init submodules (offline?); run: git submodule update --init
exit /b 0

:check
odin check src %COLLECTION% %VET% || exit /b 1
exit /b 0

:fmt
odinfmt -w src || exit /b 1
exit /b 0

:debug
odin build src %COLLECTION% %VET% -debug -out:%OUT%\grapplemap-debug.exe || exit /b 1
exit /b 0

:release
odin build src %COLLECTION% %VET% -o:speed -out:%OUT%\grapplemap.exe || exit /b 1
exit /b 0

:run
call "%~f0" debug || exit /b 1
%OUT%\grapplemap-debug.exe %2 %3 %4 %5
exit /b %errorlevel%

:test
odin test src %COLLECTION% %VET% -debug -out:%OUT%\test-main.exe || exit /b 1
exit /b 0

:ci
call "%~f0" check || exit /b 1
call "%~f0" test || exit /b 1
call "%~f0" debug || exit /b 1
call "%~f0" release || exit /b 1
exit /b 0
