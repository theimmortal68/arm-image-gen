#!/bin/bash
set -x
set -e
export LC_ALL=C
source /common.sh; install_cleanup_trap

# Fetch helper with retries (curl preferred, wget fallback)
fetch() {
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 5 --retry-delay 2 --retry-all-errors -o "$out" "$url"
  else
    wget --tries=5 --waitretry=2 --retry-connrefused -O "$out" "$url"
  fi
}

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates wget curl

CODENAME="$(. /etc/os-release; echo "${VERSION_CODENAME:-bookworm}")"
ARCH="$(dpkg --print-architecture)"
VARIANT="generic"
# If Raspberry Pi kernel package is present, use raspi variant
[ -e /etc/default/raspberrypi-kernel ] && VARIANT="raspi"

# Latest tag (best effort), fallback to pinned if API fails
TAG="$(curl -fsSL https://api.github.com/repos/ayufan/camera-streamer/releases/latest | sed -nE 's/.*"tag_name": *"v?([^"]+)".*/\1/p' | head -n1)" || true
[ -n "$TAG" ] || TAG="0.2.8"

PKG="camera-streamer-${VARIANT}_${TAG}.${CODENAME}_${ARCH}.deb"
URL="https://github.com/ayufan/camera-streamer/releases/download/v${TAG}/${PKG}"
TMP="/tmp/${PKG}"

echo_green "[camera-streamer] installing variant=${VARIANT} tag=v${TAG} arch=${ARCH} codename=${CODENAME}"

# Try codename match first, then bullseye as fallback
if ! fetch "$URL" "$TMP"; then
  ALT="camera-streamer-${VARIANT}_${TAG}.bullseye_${ARCH}.deb"
  ALT_URL="https://github.com/ayufan/camera-streamer/releases/download/v${TAG}/${ALT}"
  echo_red "[camera-streamer] ${PKG} not found, trying: ${ALT}"
  fetch "$ALT_URL" "$TMP"
fi

apt-get install -y "$TMP"

# Health checks (tolerant --help)
BIN="$(command -v camera-streamer || true)"
if [ -z "$BIN" ]; then
  echo_red "[camera-streamer] binary not found in PATH"
  exit 1
fi

if MISSING="$(ldd "$BIN" 2>/dev/null | awk '/not found/ {print $1}')" && [ -n "$MISSING" ]; then
  echo_red "[camera-streamer] missing libs: $MISSING"
  exit 1
fi

# --version must succeed
if ! "$BIN" --version >/tmp/cs.version 2>&1; then
  echo_red "[camera-streamer] --version failed"
  cat /tmp/cs.version || true
  exit 1
fi

# --help may exit non-zero; only fail if it crashes or prints nothing
CS_STATUS=0
"$BIN" --help >/tmp/cs.help 2>&1 || CS_STATUS=$?
if [ ! -s /tmp/cs.help ] || grep -qiE 'segmentation fault|illegal instruction|bus error' /tmp/cs.help; then
  echo_red "[camera-streamer] --help produced no output or crashed"
  cat /tmp/cs.help || true
  exit 1
fi

echo_green "[camera-streamer] OK: $(head -n1 /tmp/cs.version || echo 'version unknown') (help exit=${CS_STATUS})"
