#!/bin/sh
# usb-run.sh — portable Ollama-on-USB launcher (Linux + macOS).
#
# Design: the Ollama *archive* (one data file) and the model blobs live on the
# USB. The binary is extracted to a per-machine local cache and RUN FROM THERE —
# never executed directly off exFAT. exFAT can't store the .so symlinks or exec
# bits the runtime needs, and a binary run off a flaky/corrupt exFAT segfaults.
#
# !!! ALWAYS EJECT THE USB BEFORE UNPLUGGING !!!
#   udisksctl unmount -b /dev/sdXN      (or use your file manager's eject)
#   Yanking an exFAT stick mid-write corrupts files — you WILL lose the model.
#
# Usage:  ./usb-run.sh [model]          (default: gemma4:12b)

set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
# Model resolution: CLI arg > $OLLAMA_USB_MODEL env > interactive menu > default.
MODEL="${1:-${OLLAMA_USB_MODEL:-}}"
DEFAULT_MODEL="gemma4:12b"

OS=$(uname -s); ARCH=$(uname -m)
case "$OS" in
  Linux)  PLAT=linux ;;
  Darwin) PLAT=darwin ;;
  *) echo "Unsupported OS: $OS" >&2; exit 1 ;;
esac
case "$ARCH" in
  x86_64|amd64)  A=amd64 ;;
  aarch64|arm64) A=arm64 ;;
  *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;;
esac

MODELS="$ROOT/Models"                                   # model blobs (on USB)
ARCDIR="$ROOT/Ollama"                                   # downloaded archives (on USB)
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/ollama-usb/$PLAT-$A"   # extracted binary (local)
mkdir -p "$MODELS" "$ARCDIR" "$CACHE"
export OLLAMA_MODELS="$MODELS"

if [ "$PLAT" = linux ]; then ANAME="ollama-linux-$A.tar.zst"; else ANAME="ollama-darwin.tgz"; fi
ARCHIVE="$ARCDIR/$ANAME"
BASE="https://github.com/ollama/ollama/releases/latest/download"

dl() {  # dl <url> <out>
  if   command -v curl >/dev/null 2>&1; then curl -fSL "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then wget -O "$2" "$1"
  else echo "need curl or wget installed" >&2; exit 1
  fi
}

extract() {  # extract archive into the (already emptied) cache dir
  case "$ANAME" in
    *.tar.zst)
      if   tar --help 2>/dev/null | grep -q -- '--zstd'; then tar --zstd -xf "$ARCHIVE" -C "$CACHE"
      elif command -v zstd >/dev/null 2>&1;             then zstd -dc "$ARCHIVE" | tar -xf - -C "$CACHE"
      else echo "need 'zstd' installed (or a tar that supports --zstd)" >&2; exit 1
      fi ;;
    *) tar -xzf "$ARCHIVE" -C "$CACHE" ;;               # macOS .tgz
  esac
}

choose_model() {  # interactive picker; sets MODEL. Needs the server running.
  echo
  echo "Models already on this USB:"
  "$BIN" list 2>/dev/null | awk 'NR>1 && $1!="" {print "   " $1}'
  echo
  echo "Choose a model to download/run:"
  echo "   1) gemma3:12b         general purpose (Google)"
  echo "   2) llama3.2:3b        small & fast (Meta)"
  echo "   3) qwen2.5-coder:7b   coding"
  echo "   4) phi4:14b           reasoning (Microsoft)"
  echo "   5) mistral:7b         general purpose"
  echo "   6) $DEFAULT_MODEL         default"
  echo "   7) custom — any Ollama name, or hf.co/<user>/<repo>:<quant>"
  printf "Selection [6]: "
  read -r sel
  case "$sel" in
    1) MODEL="gemma3:12b" ;;
    2) MODEL="llama3.2:3b" ;;
    3) MODEL="qwen2.5-coder:7b" ;;
    4) MODEL="phi4:14b" ;;
    5) MODEL="mistral:7b" ;;
    7) printf "Enter model name: "; read -r MODEL ;;
    *) MODEL="$DEFAULT_MODEL" ;;
  esac
}

# 1. Make sure the archive is on the USB (downloaded once; reused on any machine).
if [ ! -s "$ARCHIVE" ]; then
  echo "Downloading $ANAME to USB ..."
  dl "$BASE/$ANAME" "$ARCHIVE.part"
  mv "$ARCHIVE.part" "$ARCHIVE"
fi

# 2. Extract to the local cache (real filesystem — symlinks + exec work here).
if [ ! -e "$CACHE/.complete" ]; then
  echo "Extracting Ollama to local cache ($CACHE) ..."
  rm -rf "$CACHE"; mkdir -p "$CACHE"
  extract
  : > "$CACHE/.complete"
fi

BIN="$CACHE/bin/ollama"
[ -e "$BIN" ] || BIN="$(find "$CACHE" -type f -name ollama 2>/dev/null | head -n1)"
chmod +x "$BIN" 2>/dev/null || true

# 3. Sanity check — a corrupt archive (e.g. USB yanked mid-write) won't run.
if ! "$BIN" --version >/dev/null 2>&1; then
  echo "Ollama binary is broken — the archive on the USB is likely corrupt." >&2
  echo "(Did you unplug the USB without ejecting?) Clearing it; re-run to re-fetch." >&2
  rm -f "$ARCHIVE"; rm -rf "$CACHE"
  exit 1
fi

# 4. Serve, wait for ready, pull, run.
"$BIN" serve >/dev/null 2>&1 &
SRV=$!
trap 'kill "$SRV" 2>/dev/null || true' EXIT INT TERM

i=0
until "$BIN" list >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -ge 30 ]; then echo "Ollama server did not start" >&2; exit 1; fi
  sleep 1
done

# --list just shows what's installed and exits.
if [ "$MODEL" = "--list" ] || [ "$MODEL" = "list" ]; then
  "$BIN" list
  exit 0
fi

# No model given? Ask (interactive), or fall back to the default if non-interactive.
if [ -z "$MODEL" ]; then
  if [ -t 0 ]; then choose_model; else MODEL="$DEFAULT_MODEL"; fi
fi

echo "Pulling $MODEL ..."
"$BIN" pull "$MODEL"

"$BIN" run "$MODEL"

echo
echo ">>> Done. EJECT the USB before unplugging:  udisksctl unmount -b /dev/sdXN  <<<"
