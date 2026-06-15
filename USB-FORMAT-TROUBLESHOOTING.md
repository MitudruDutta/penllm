# Troubleshooting: formatting a USB as exFAT on Linux

You need the USB formatted as **exFAT** (model files exceed FAT32's 4 GB limit).
But a USB that was previously used on Linux often **refuses to format or mount**,
with confusing errors. This guide fixes every variant of that problem.

> ⚠️ Everything here **erases the USB**. Be 100% sure `/dev/sdX` is the USB and
> not an internal disk. Check the size with `lsblk` first.

---

## TL;DR — the clean-slate fix

If you just want it working, run this on **the USB partition** (replace `sda1`
with yours). It force-erases *every* leftover signature, then formats fresh:

```bash
DEV=/dev/sda1                              # <-- set to YOUR USB partition

udisksctl unmount -b "$DEV" 2>/dev/null    # ignore "not mountable" — that's fine
sudo wipefs -af "$DEV"                      # erase ALL old signatures (force)
sudo mkfs.exfat -F -n OLLAMA "$DEV"         # format exFAT (force past stragglers)
sudo udevadm trigger --settle "$DEV"        # make the kernel re-read it
lsblk -f /dev/sda                           # expect: exfat  OLLAMA  on sda1
udisksctl mount -b "$DEV"                   # mounts at /run/media/$USER/OLLAMA
```

If `lsblk -f` shows `exfat OLLAMA` and `udisksctl mount` prints a path — done.

---

## Why this is hard: ghost signatures

`mkfs.exfat` only zeroes the **first 64 KB** (`0x0`–`0x10000`) of the device.
A previous **btrfs** filesystem keeps its superblock at offset **`0x10040`** —
*just past* what the format wipes. So after "format complete!" the device has
**two filesystem signatures at once**: the new exFAT *and* the old btrfs.

`blkid` / `lsblk` see the ambiguity, report **no filesystem type**, and the auto-
mounter says *"not a mountable filesystem."* The format looked successful but the
drive won't mount.

The fix is to erase **all** signatures (`wipefs -a`) before/along with the format —
not just rely on `mkfs`.

---

## Symptom → cause → fix

| What you see | Cause | Fix |
|---|---|---|
| `mkfs.exfat`: `open failed ... Device or resource busy` | Partition still mounted (the desktop auto-mounter re-mounted it). | `udisksctl unmount -b /dev/sda1`, then format. Don't use `umount ... \|\| true` — it hides the failure. |
| `udisksctl unmount`: `is not a mountable filesystem` | It isn't mounted (or has ambiguous signatures). Safe to ignore *if* you're about to reformat. | Continue to `wipefs`/`mkfs`. |
| `lsblk -f` shows **blank** FSTYPE after a "successful" format | Multiple signatures present (e.g. old **btrfs** at `0x10040` + new exFAT). blkid can't decide. | `sudo wipefs -af /dev/sda1` then re-format. |
| `udisksctl mount`: `not a mountable filesystem` | Same ambiguity, or kernel hasn't re-probed yet. | `sudo udevadm trigger --settle /dev/sda1`, or unplug+replug. If still failing, reformat clean. |
| `wipefs -a`: `ignoring nested "dos" partition table ... Use the --force option` | A leftover MBR/boot (`dos`) signature wipefs won't touch without force. | Add `-f`: `sudo wipefs -af /dev/sda1`. |
| `mkfs.exfat`: `Device has existing signatures. Refusing to overwrite; use -F to force.` | A signature still on the device (often the `dos`/`0x55AA` boot marker). | `sudo mkfs.exfat -F -n OLLAMA /dev/sda1`. |
| After everything, `wipefs` still lists a `dos` at `0x1fe` | That's exFAT's **own** boot-sector marker (`0x55AA`). Normal. | Ignore. Only a leftover **`btrfs`/`ext4`/`ntfs`** line is a problem. |

---

## Step-by-step (when the TL;DR isn't enough)

**1. Identify the USB — do not guess.**
```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT,MODEL
```
Match by size and `MODEL` (e.g. `USB Flash Drive`). Note the partition, e.g. `sda1`.

**2. See exactly what signatures are on it (read-only):**
```bash
sudo wipefs /dev/sda1
```
Example of a *broken* drive — note the stale `btrfs`:
```
DEVICE OFFSET  TYPE  UUID                                 LABEL
sda1   0x10040 btrfs 8d73ca26-c858-4e2f-8c50-ba517f117f27
sda1   0x3     exfat 6BBA-34BB                            OLLAMA
sda1   0x1fe   dos
```
Two filesystems (`btrfs` + `exfat`) = the drive won't mount.

**3. Unmount, erase all signatures, reformat:**
```bash
udisksctl unmount -b /dev/sda1 2>/dev/null
sudo wipefs -af /dev/sda1
sudo mkfs.exfat -F -n OLLAMA /dev/sda1
```

**4. Confirm only exFAT remains:**
```bash
sudo wipefs /dev/sda1     # should show exfat (and maybe a harmless dos 0x1fe) — NO btrfs/ext4
sudo udevadm trigger --settle /dev/sda1
lsblk -f /dev/sda         # sda1 -> exfat  OLLAMA
```

**5. Mount:**
```bash
udisksctl mount -b /dev/sda1
findmnt -no TARGET /dev/sda1     # prints e.g. /run/media/youruser/OLLAMA
```
If `udisksctl` still won't mount, **unplug and replug** the USB — the desktop
auto-mounter picks up the now-unambiguous filesystem.

---

## Nuclear option: wipe the whole disk and repartition

If signatures keep reappearing, erase the entire device (not just the partition)
and lay down a fresh partition table:

```bash
DISK=/dev/sda                     # the WHOLE disk, no partition number

udisksctl unmount -b ${DISK}1 2>/dev/null
sudo wipefs -af "$DISK"           # nuke every signature on the whole device
sudo sgdisk --zap-all "$DISK"     # clear GPT + MBR (from gdisk package)
sudo dd if=/dev/zero of="$DISK" bs=1M count=16 status=progress  # zero the front
# new GPT + one partition spanning the disk:
sudo sgdisk -n 1:0:0 -t 1:0700 "$DISK"
sudo mkfs.exfat -n OLLAMA "${DISK}1"
sudo udevadm trigger --settle
lsblk -f "$DISK"
```
(`sgdisk` is in the `gdisk` package: `sudo dnf install -y gdisk`.)

---

## After it mounts

Back to [INSTALL.md](INSTALL.md) — copy the launcher files to the USB root and
run. In short:
```bash
MP=$(findmnt -no TARGET /dev/sda1)
cp usb-run.sh usb-download.ps1 start.bat README.md INSTALL.md "$MP"/
chmod +x "$MP"/usb-run.sh
cd "$MP" && ./usb-run.sh
```
