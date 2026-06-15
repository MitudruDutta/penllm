# usb-download.ps1 — set up portable Ollama on the USB (Windows) using the
# standalone zip: no installer, no admin rights, no registry/host traces.
# The Ollama archive + binary and the model blobs all live on the USB.
#
# !!! ALWAYS use "Safely Remove Hardware" / Eject before unplugging the USB !!!
#     Yanking an exFAT stick mid-write corrupts files and loses the model.
#
# Usage:  powershell -ExecutionPolicy Bypass -File usb-download.ps1 [model]
#         default model: gemma4:12b

$ErrorActionPreference = 'Stop'

$Root      = $PSScriptRoot                       # USB folder where this script sits
$OllamaDir = Join-Path $Root "Ollama"
$ModelsDir = Join-Path $Root "Models"
$Model     = if ($args.Count -ge 1) { $args[0] } else { "gemma4:12b" }

$Arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "amd64" }
$Zip  = "ollama-windows-$Arch.zip"
$Url  = "https://github.com/ollama/ollama/releases/latest/download/$Zip"

New-Item -ItemType Directory -Force -Path $OllamaDir, $ModelsDir | Out-Null
$env:OLLAMA_MODELS = $ModelsDir
$OllamaExe = Join-Path $OllamaDir "ollama.exe"

# Download the zip to the USB (once) and extract. Windows .exe/.dll have no
# symlinks, so running straight off the USB is fine — no local cache needed.
if (!(Test-Path $OllamaExe)) {
    $ZipPath = Join-Path $OllamaDir $Zip
    if (!(Test-Path $ZipPath)) {
        Write-Host "Downloading $Zip to USB ..."
        Invoke-WebRequest -Uri $Url -OutFile "$ZipPath.part"
        Move-Item "$ZipPath.part" $ZipPath -Force
    }
    Write-Host "Extracting Ollama ..."
    Expand-Archive -Path $ZipPath -DestinationPath $OllamaDir -Force
}
if (!(Test-Path $OllamaExe)) { Write-Error "ollama.exe not found after extract"; exit 1 }

# Start the server.
Write-Host "Starting Ollama server..."
Start-Process -FilePath $OllamaExe -ArgumentList "serve" -WindowStyle Hidden

# Poll until the server answers (max ~30s).
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    & $OllamaExe list *> $null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Seconds 1
}
if (-not $ready) { Write-Error "Ollama server did not become ready"; exit 1 }

# Pull the model.
Write-Host "Downloading $Model ..."
& $OllamaExe pull $Model
if ($LASTEXITCODE -ne 0) { Write-Error "Pull failed for $Model"; exit 1 }

# Write start.bat next to this script (%~dp0 makes it work wherever the USB mounts).
$StartBat = @"
@echo off
setlocal
set OLLAMA_MODELS=%~dp0Models

if "%~1"=="" ( set "MODEL=$Model" ) else ( set "MODEL=%~1" )

start "" "%~dp0Ollama\ollama.exe" serve

rem wait until the server is ready (max ~30s)
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
"@
Set-Content -Path (Join-Path $Root "start.bat") -Value $StartBat -Encoding ASCII

Write-Host ""
Write-Host "Done. Default model: $Model"
Write-Host "Run later with:  start.bat   (or  start.bat <model>)"
Write-Host "REMEMBER: Safely Remove / Eject the USB before unplugging."
