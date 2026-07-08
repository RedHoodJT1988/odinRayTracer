@echo off
setlocal

set SRC_DIR=src
set OUT_NAME=raytracer.exe

if /I "%1"=="release" goto :release
if /I "%1"=="clean" goto :clean
goto :debug

:debug
echo [build] debug build (-debug, no optimization)
odin build %SRC_DIR% -out:%OUT_NAME% -debug
goto :check

:release
echo [build] release build (-o:speed)
odin build %SRC_DIR% -out:%OUT_NAME% -o:speed -no-bounds-check
goto :check

:clean
echo [build] removing build artifacts
if exist %OUT_NAME% del %OUT_NAME%
if exist %OUT_NAME:.exe=.pdb% del %OUT_NAME:.exe=.pdb%
goto :eof

:check
if %ERRORLEVEL% neq 0 (
    echo [build] FAILED
    exit /b %ERRORLEVEL%
)
echo [build] OK -^> %OUT_NAME%
echo [build] run with: %OUT_NAME%
goto :eof

endlocal
