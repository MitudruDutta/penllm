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
# Private port so we don't collide with an Ollama already running on this PC
# (default :11434) — otherwise pulls go to the system disk instead of the USB.
$env:OLLAMA_HOST = "127.0.0.1:11435"
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

Write-Host ""
Write-Host "Done. Pulled model: $Model"
Write-Host "Run any time with:  start.bat            (shows a model menu)"
Write-Host "                or:  start.bat <model>   (e.g. start.bat llama3.2:3b)"
Write-Host "REMEMBER: Safely Remove / Eject the USB before unplugging."
