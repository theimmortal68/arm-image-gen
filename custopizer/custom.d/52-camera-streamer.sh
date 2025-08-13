#!/bin/bash
set -x
set -e
export LC_ALL=C
source /common.sh
install_cleanup_trap
export DEBIAN_FRONTEND=noninteractive

retry 4 2 apt-get update
apt-get install -y --no-install-recommends ca-certificates wget curl

CODENAME="$(. /etc/os-release; echo "${VERSION_CODENAME:-bookworm}")"
ARCH="$(dpkg --print-architecture)"

VARIANT="generic"
if [ -e /etc/default/raspberrypi-kernel ]; then VARIANT="raspi"; fi

TAG="$(curl -fsSL https://api.github.com/repos/ayufan/camera-streamer/releases/latest \
       | grep -m1 '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/')" || true
[ -n "$TAG" ] || TAG="0.2.7"

PKG="camera-streamer-${VARIANT}_${TAG}.${CODENAME}_${ARCH}.deb"
URL="https://github.com/ayufan/camera-streamer/releases/download/v${TAG}/${PKG}"
TMP="/tmp/${PKG}"

echo_green "[camera-streamer] installing variant=${VARIANT} tag=v${TAG} arch=${ARCH} codename=${CODENAME}"

if ! wget -O "$TMP" "$URL"; then
  ALT="camera-streamer-${VARIANT}_${TAG}.bullseye_${ARCH}.deb"
  ALT_URL="https://github.com/ayufan/camera-streamer/releases/download/v${TAG}/${ALT}"
  echo_red "[camera-streamer] Bookworm asset not found, trying: ${ALT_URL}"
  wget -O "$TMP" "$ALT_URL"
fi

apt-get install -y "$TMP"

BIN="$(command -v camera-streamer || true)"
if [ -z "$BIN" ]; then echo_red "[camera-streamer] ERROR: binary not found"; exit 1; fi
if MISSING="$(ldd "$BIN" | awk '/not found/ {print $1}')" && [ -n "$MISSING" ]; then
  echo_red "[camera-streamer] ERROR: missing libs: $MISSING"; exit 1
fi
if ! "$BIN" --version >/tmp/cs.version 2>&1; then
  echo_red "[camera-streamer] ERROR: --version failed"; cat /tmp/cs.version || true; exit 1
fi
if ! "$BIN" --help >/dev/null 2>&1; then
  echo_red "[camera-streamer] ERROR: --help failed"; exit 1
fi
echo_green "[camera-streamer] OK: $(head -n1 /tmp/cs.version || echo 'version unknown')"
