@echo off
setlocal
cd /d "%~dp0"
set COLLECTION=-collection:app=src
set VET=-vet -strict-style -warnings-as-errors
set OUT=build
if not exist %OUT% mkdir %OUT%

if "%1"=="setup"        ( git config core.hooksPath .githooks & echo hooks activated & exit /b 0 )
if "%1"=="check"        ( odin check src %COLLECTION% %VET% & exit /b %errorlevel% )
if "%1"=="fmt"          ( odinfmt -w src & exit /b %errorlevel% )
if "%1"=="fmt-check"    ( echo fmt-check: run on Linux/macOS CI & exit /b 0 )
if "%1"=="debug"        ( odin build src %COLLECTION% %VET% -debug -out:%OUT%\grapplemap-debug.exe & exit /b %errorlevel% )
if "%1"=="release"      ( odin build src %COLLECTION% %VET% -o:speed -out:%OUT%\grapplemap.exe & exit /b %errorlevel% )
if "%1"=="run"          ( call %0 debug && %OUT%\grapplemap-debug.exe & exit /b %errorlevel% )
if "%1"=="test"         ( odin test src %COLLECTION% %VET% -debug -out:%OUT%\test-main.exe & exit /b %errorlevel% )
if "%1"=="test-golden"  ( echo golden tests arrive in phase 3 & exit /b 0 )
if "%1"=="bench"        ( echo no benchmarks yet & exit /b 0 )
if "%1"=="ci"           ( call %0 check && call %0 test && call %0 debug && call %0 release & exit /b %errorlevel% )
echo usage: build.bat {setup^|check^|fmt^|fmt-check^|debug^|release^|run^|test^|test-golden^|bench^|ci}
exit /b 2
