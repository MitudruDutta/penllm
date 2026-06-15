@echo off
setlocal
set OLLAMA_MODELS=%~dp0Models

if "%~1"=="" ( set "MODEL=gemma4:12b" ) else ( set "MODEL=%~1" )

start "" "%~dp0Ollama\ollama.exe" serve

rem wait until the server is ready (max ~30s) instead of a fixed timeout
set /a tries=0
:waitloop
"%~dp0Ollama\ollama.exe" list >nul 2>&1
if not errorlevel 1 goto ready
set /a tries+=1
if %tries% geq 30 ( echo Ollama server did not start & exit /b 1 )
timeout /t 1 >nul
goto waitloop
:ready

"%~dp0Ollama\ollama.exe" run %MODEL%

echo.
echo ^>^>^> Done. Use "Safely Remove Hardware" / Eject before unplugging the USB. ^<^<^<
endlocal
