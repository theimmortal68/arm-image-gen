#!/usr/bin/env bash
# Optional: fetch official Raspberry Pi OS Lite arm64 and save as input image.
# Usage: fetch-raspios.sh [out_img]
set -euo pipefail

OUT_IMG="${1:-build/input-rpi64.img}"
TMPDIR="$(mktemp -d)"
mkdir -p "$(dirname "$OUT_IMG")"

need() { command -v "$1" >/dev/null 2>&1 || { sudo apt-get update && sudo apt-get install -y "$1"; }; }

need curl
need xz-utils
need unzip
need file
need dd

RPIOS_URL="${RPIOS_URL:-https://downloads.raspberrypi.com/raspios_lite_arm64_latest}"
echo "[raspios] Fetching $RPIOS_URL"

cd "$TMPDIR"
curl -fL -o raspios.latest "$RPIOS_URL"

if file raspios.latest | grep -qi zip; then
  unzip -p raspios.latest | dd of=raspios.img bs=4M status=none
elif file raspios.latest | grep -qi xz; then
  xz -dc raspios.latest > raspios.img
else
  mv raspios.latest raspios.img
fi

if [ ! -s raspios.img ]; then
  unzip -d unz raspios.latest >/dev/null 2>&1 || true
  IMG_PATH="$(find . -type f -name '*.img' | head -n1 || true)"
  [ -n "$IMG_PATH" ] || { echo "No .img found in archive"; exit 1; }
  cp -f "$IMG_PATH" raspios.img
fi

mv -f raspios.img "$(pwd)/../$OUT_IMG"
echo "[raspios] Saved to $OUT_IMG"
