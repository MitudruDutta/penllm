# penllm

Portable local LLM on a USB stick — carry a model and run it on any machine.

Run a local LLM straight from a USB stick. The Ollama archive and the model
blobs live on the USB; the binary is extracted to a small per-machine cache and
run from there. The same drive works on any machine.

> ⚠️ **Always eject the USB before unplugging** — `udisksctl unmount -b /dev/sdXN`
> (Linux) or "Safely Remove Hardware" (Windows) / drag-to-eject (macOS). exFAT
> corrupts if yanked mid-write and you will lose the model.

> **New here?** Follow **[INSTALL.md](INSTALL.md)** for the full step-by-step setup.
> Stuck formatting the USB on Linux? See **[USB-FORMAT-TROUBLESHOOTING.md](USB-FORMAT-TROUBLESHOOTING.md)**.

## Requirement: filesystem MUST be exFAT or NTFS

Model blobs are single files larger than FAT32's 4 GB limit (gemma4:12b Q4 is
~8 GB). Format the USB as **exFAT** (cross-platform) before use:

```bash
lsblk -f                          # find the USB partition, check its FS
sudo mkfs.exfat -n OLLAMA /dev/sdXN   # WIPES the partition — back up first
```

## Layout

```
<USB>/
  Models/                  shared model blobs (all OSes use this)
  Ollama/                  downloaded Ollama archives (created on first run)
    ollama-linux-amd64.tar.zst
    ollama-darwin.tgz
    ...                    (binary is extracted to ~/.cache, not run off USB)
  usb-run.sh               Linux + macOS launcher
  usb-download.ps1         Windows installer (run once)
  start.bat                Windows launcher (created/used after install)
```

## Run it

### Linux / macOS
```bash
./usb-run.sh                 # default model: gemma4:12b
./usb-run.sh gemma3:12b      # any other model
```
First run downloads the right Ollama binary onto the USB, starts the server,
pulls the model, then opens a chat.

### Windows
```powershell
powershell -ExecutionPolicy Bypass -File usb-download.ps1   # once, installs Ollama to USB + pulls model
.\start.bat                                                 # thereafter: start.bat [model]
```

## Notes / fallbacks

- **`gemma4:12b` not on the Ollama registry yet?** `pull` will 404. Use a known
  base instead — `gemma3:12b` — or the GGUF build:
  `./usb-run.sh hf.co/yuxinlu1/gemma-4-12B-coder-fable5-composer2.5-v1-GGUF:Q4_K_M`
  (that one is a third-party, unofficial upload — quality unverified).
- **RAM**: a 12B model at Q4 needs ~9–10 GB free RAM. CPU-only inference is slow
  (a few tokens/sec). Don't raise `num_ctx` toward the 131K max — KV cache eats
  gigabytes of RAM.
- **USB speed** only affects model load time (the ~8 GB file is read into RAM
  once). Inference runs in RAM, not off the USB.
- **macOS Gatekeeper** may block an unsigned binary copied off a USB. If macOS
  refuses to run it: `xattr -dr com.apple.quarantine "<USB>/Ollama"`, or
  `brew install ollama` and re-run (the script uses whatever it finds).
