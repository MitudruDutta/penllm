@echo off
setlocal enabledelayedexpansion
set OLLAMA_MODELS=%~dp0Models
rem Use a private port so we don't collide with any Ollama already running on
rem this PC (default :11434) — otherwise pulls go to the system disk, not the USB.
set OLLAMA_HOST=127.0.0.1:11435

rem Model: use the argument if given, otherwise show a menu.
if not "%~1"=="" ( set "MODEL=%~1" & goto serve )

echo Choose a model to download/run:
echo    1^) gemma3:12b         general purpose (Google)
echo    2^) llama3.2:3b        small ^& fast (Meta)
echo    3^) qwen2.5-coder:7b   coding
echo    4^) phi4:14b           reasoning (Microsoft)
echo    5^) mistral:7b         general purpose
echo    6^) gemma4:12b         default
echo    7^) custom - any Ollama name, or hf.co/^<user^>/^<repo^>:^<quant^>
set /p "sel=Selection [6]: "
if "!sel!"=="1" set "MODEL=gemma3:12b"
if "!sel!"=="2" set "MODEL=llama3.2:3b"
if "!sel!"=="3" set "MODEL=qwen2.5-coder:7b"
if "!sel!"=="4" set "MODEL=phi4:14b"
if "!sel!"=="5" set "MODEL=mistral:7b"
if "!sel!"=="7" set /p "MODEL=Enter model name: "
if not defined MODEL set "MODEL=gemma4:12b"

:serve
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

rem only download if the model isn't already on the USB (avoids a slow re-verify)
"%~dp0Ollama\ollama.exe" show !MODEL! >nul 2>&1
if errorlevel 1 (
  echo Pulling !MODEL! ...
  "%~dp0Ollama\ollama.exe" pull !MODEL!
) else (
  echo !MODEL! is already on the USB - starting it.
)
"%~dp0Ollama\ollama.exe" run !MODEL!

echo.
echo ^>^>^> Done. Use "Safely Remove Hardware" / Eject before unplugging the USB. ^<^<^<
endlocal
