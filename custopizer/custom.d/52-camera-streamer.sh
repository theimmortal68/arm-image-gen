#!/usr/bin/env bash
set -Eeuxo pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap
export DEBIAN_FRONTEND=noninteractive

PIN_FILE="/files/etc/camera-streamer.version"
TAG_DEFAULT="0.2.8"

read_pin() {
  local t=""
  if [ -f "$PIN_FILE" ]; then t="$(sed -e 's/^[vV]//' -e 's/[^0-9A-Za-z._-].*$//' "$PIN_FILE" | head -n1)"
  elif [ -n "${CAMERA_STREAMER_TAG:-}" ]; then t="$(printf '%s' "$CAMERA_STREAMER_TAG" | sed 's/^[vV]//')"
  fi; printf '%s' "${t:-}"
}
TAG="$(read_pin || true)"; [ -n "$TAG" ] || TAG="$TAG_DEFAULT"

ARCH="$(dpkg --print-architecture)"
VARIANT="generic"; [ -e /etc/default/raspberrypi-kernel ] && VARIANT="raspi"
case "$ARCH" in arm64|aarch64) ASSET_ARCH="linux_aarch64";; armhf|armel|arm) ASSET_ARCH="linux_armv7";; *) echo "[camera-streamer] unsupported arch: $ARCH"; exit 2;; esac

BIN="/usr/local/bin/camera-streamer"
TMP=$(mktemp -d)

# Prefer a staged binary if present
if [ -x /files/usr/local/bin/camera-streamer ]; then
  install -Dm0755 /files/usr/local/bin/camera-streamer "$BIN"
  echo "[camera-streamer] installed staged binary from /files"
else
  if [ -x "$BIN" ] && [ ! -f "$PIN_FILE" ] && [ -z "${CAMERA_STREAMER_TAG:-}" ]; then
    echo "[camera-streamer] existing binary; no pin requested"
  else
    apt-get update || true
    apt-get install -y --no-install-recommends ca-certificates curl tar xz-utils || true
    ASSET="camera-streamer_${TAG}_${ASSET_ARCH}.tar.gz"
    URL="https://github.com/ayufan/camera-streamer/releases/download/v${TAG}/${ASSET}"
    curl -fL --retry 5 --retry-delay 2 --retry-all-errors -o "${TMP}/cs.tgz" "$URL"
    tar -xzf "${TMP}/cs.tgz" -C "$TMP"
    CS_PATH="$(find "$TMP" -type f -name 'camera-streamer' -perm -111 | head -n1 || true)"
    [ -n "$CS_PATH" ] || { echo "[camera-streamer] binary not found in archive"; exit 1; }
    install -Dm0755 "$CS_PATH" "$BIN"
  fi
fi

# Health checks
set +e
"$BIN" --version > /tmp/cs.version 2>&1; CS_VERS_RC=$?
set -e
[ $CS_VERS_RC -eq 0 ] && grep -qE 'camera-streamer|version|^v?[0-9]+\.' /tmp/cs.version
"$BIN" --help >/tmp/cs.help 2>&1 || true
! grep -qiE 'segmentation fault|illegal instruction|bus error' /tmp/cs.help

echo "[camera-streamer] OK: $(head -n1 /tmp/cs.version || echo 'version unknown')"

# Libcamera sanity (RPi only)
if [ "$VARIANT" = "raspi" ]; then
  (apt-cache policy libcamera0 2>/dev/null | sed -n '1,20p') || true
  dpkg -l | awk '/^ii/ && /libcamera|v4l2|raspberrypi/ {printf "[pkg] %-40s %s\n",$2,$3}' || true
  ldconfig -p 2>/dev/null | grep -E 'libcamera|v4l2' || true
  install -d /boot/firmware
  grep -q '^dtoverlay=vc4-kms-v3d' /boot/firmware/config.txt 2>/dev/null || echo "dtoverlay=vc4-kms-v3d" >> /boot/firmware/config.txt
fi
