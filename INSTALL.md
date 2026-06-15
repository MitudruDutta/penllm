# Install — Portable LLM on USB

Step-by-step setup. Do **Part 1 once** to prepare the stick. After that, just
run it (Part 4) on any machine.

You need a USB drive of **at least 16 GB** (32 GB+ recommended if you want more
than one model). USB 3.0 strongly preferred — load time scales with USB speed.

---

## Part 1 — Format the USB as exFAT (mandatory)

The model is one file bigger than 4 GB, which **FAT32 cannot store**. exFAT has
no practical size limit and is read/write on Windows, macOS, and Linux. Do this
once, on whichever computer is handy.

> ⚠️ Formatting **erases the entire drive**. Back up anything on it first, and
> be certain you picked the USB and not an internal disk.

### On Linux (Fedora)

1. Install the exFAT tools:
   ```bash
   sudo dnf install -y exfatprogs
   ```
2. Plug in the USB. Find its device name — run this **before and after**
   plugging in and see which entry is new. Match it by size (e.g. `28.6G`):
   ```bash
   lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,MODEL
   ```
   Say it shows up as `sdb` with one partition `sdb1`. **Confirm the size is
   your USB, not your system disk**, then continue using *your* device name.
3. Unmount the partition. Use `udisksctl` so the desktop auto-mounter does not
   immediately remount it (replace `sdb1` with your partition):
   ```bash
   udisksctl unmount -b /dev/sdb1
   lsblk -o NAME,MOUNTPOINT /dev/sdb        # MOUNTPOINT should now be blank
   ```
   If a later step reports "Device or resource busy", something still has it
   open — find and close it, then unmount again:
   ```bash
   sudo fuser -vm /dev/sdb1                  # lists PIDs using the device
   ```
4. Format the partition as exFAT (replace `sdb1` with your partition):
   ```bash
   sudo mkfs.exfat -n OLLAMA /dev/sdb1
   ```
   If the drive has no partition at all, create one first with
   `sudo fdisk /dev/sdb` (`n`, accept defaults, `w`), then format `sdb1`.

> **Format errors or "not a mountable filesystem"?** A USB previously used on
> Linux often has leftover filesystem signatures that block the format/mount.
> See **[USB-FORMAT-TROUBLESHOOTING.md](USB-FORMAT-TROUBLESHOOTING.md)** for the
> one-shot fix.
5. Re-plug the USB so the file manager mounts it (usually at
   `/run/media/$USER/OLLAMA`).

### On Windows

1. Open **File Explorer** → right-click the USB drive → **Format…**
2. File system: **exFAT**. Volume label: `OLLAMA`. Click **Start**.

### On macOS

1. Open **Disk Utility** → select the USB device (the top-level entry, not the
   volume) → **Erase**.
2. Format: **exFAT**. Scheme: **GUID Partition Map**. Name: `OLLAMA`. **Erase**.

---

## Part 2 — Copy the launcher files onto the USB

Copy these four files from this repository to the **root** of the USB
(the top level, not inside a folder):

```
usb-run.sh         ← Linux / macOS launcher
usb-download.ps1   ← Windows installer
start.bat          ← Windows launcher
README.md          ← reference (optional)
```

On Linux, with the USB mounted at `/run/media/$USER/OLLAMA`:
```bash
cp usb-run.sh usb-download.ps1 start.bat README.md /run/media/$USER/OLLAMA/
chmod +x /run/media/$USER/OLLAMA/usb-run.sh
```

After this the USB root looks like:
```
OLLAMA/
  usb-run.sh
  usb-download.ps1
  start.bat
  README.md
```
The `Ollama/` (downloaded archive) and `Models/` (model files) folders are
created automatically on first run — you don't make them by hand. The Ollama
binary itself is extracted to `~/.cache/ollama-usb/` and run from there, never
off the USB.

---

## Part 3 — First run (downloads Ollama + the model)

First run needs **internet** — it downloads the Ollama binary and the model
onto the USB. This is a multi-GB download; let it finish.

### Linux / macOS
```bash
cd /run/media/$USER/OLLAMA      # or wherever the USB is mounted
./usb-run.sh
```

### Windows
Open PowerShell, `cd` to the USB drive (e.g. `E:\`), then:
```powershell
powershell -ExecutionPolicy Bypass -File usb-download.ps1
```

When it finishes you land in a chat prompt with the model. Type a message;
`/bye` exits.

---

## Part 4 — Every run after that

The binary and model are already on the USB — no more downloads, no internet
needed.

### Linux / macOS
```bash
./usb-run.sh                 # default model
./usb-run.sh gemma3:12b      # a different model
```

### Windows
```powershell
.\start.bat
.\start.bat gemma3:12b
```

---

## Eject before unplugging — do not skip

exFAT buffers writes. If you pull the USB without ejecting, the model and even
the Ollama binary get corrupted and you have to re-download everything. Every
time, before removing the stick:

```bash
udisksctl unmount -b /dev/sda1        # replace with your partition
```
Or use your file manager's "Eject" / "Safely Remove". On Windows use the system
tray "Safely Remove Hardware"; on macOS drag the volume to the Trash / eject.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Error: ... file too large` while pulling | USB is still FAT32. Redo Part 1 as exFAT. |
| `tar: Cannot create symlink ... Operation not permitted` | exFAT has no symlinks. `usb-run.sh` avoids this by extracting the binary to `~/.cache`, not onto the USB — just re-run `./usb-run.sh`. |
| `Segmentation fault` / `file ... too large section header offset` | The archive/binary is corrupt — almost always from **unplugging the USB without ejecting**. The script auto-clears it; just re-run `./usb-run.sh` to re-fetch. |
| Model gone / `Models/` is empty after a working run | Same cause: USB yanked mid-write. Re-pull. **Eject before unplugging.** |
| `curl: (22) ... 404` downloading Ollama | Release asset name changed. The script targets `releases/latest`; update it if Ollama renames assets again. |
| `pull` fails with 404 / model not found | `gemma4:12b` not on the registry. Use `gemma3:12b`, or the GGUF: `./usb-run.sh hf.co/yuxinlu1/gemma-4-12B-coder-fable5-composer2.5-v1-GGUF:Q4_K_M` (unofficial, unverified). |
| `Permission denied` running the binary (Linux/macOS) | exFAT drops the exec bit; the script auto-copies to a temp dir and runs there. If it still fails, check `/tmp` is writable. |
| macOS: "cannot be opened because the developer cannot be verified" | `xattr -dr com.apple.quarantine "<USB>/Ollama"` then re-run, or `brew install ollama` and re-run. |
| `Ollama server did not start` | Another `ollama serve` may already hold port 11434. Stop it, or just run `ollama run <model>` against the existing server. |
| Very slow generation | 12B on CPU is a few tokens/sec. Use a smaller model (`gemma3:4b`) or a machine with a supported GPU. |
| Out of memory | 12B Q4 needs ~9–10 GB free RAM. Close apps, or use a smaller model. |

## Hardware reality check

- **RAM**: ≥ 12 GB free for `gemma4:12b` Q4. Below that, use a 4B model.
- **USB speed** only affects how long the model takes to load into RAM (the
  ~8 GB file is read once per run). Generation happens in RAM, not off the USB.
