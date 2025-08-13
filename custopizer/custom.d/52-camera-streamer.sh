#!/bin/bash
# Install camera-streamer from the latest release.
# - Variant: raspi on Raspberry Pi; generic on others (OPi/RK3588, etc.)
# - Prefers Bookworm .deb, falls back to Bullseye if needed.
# - Includes a non-fatal health check.

set -x
set -e
export LC_ALL=C

source /common.sh
install_cleanup_trap

export DEBIAN_FRONTEND=noninteractive

# Minimal tooling
apt-get update
apt-get install -y --no-install-recommends ca-certificates wget curl || true

# Detect codename/arch
CODENAME="$(. /etc/os-release; echo "${VERSION_CODENAME:-bookworm}")"
ARCH="$(dpkg --print-architecture)"

# Pick variant per upstream guidance: raspi if Pi kernel defaults exist, else generic
VARIANT="generic"
if [ -e /etc/default/raspberrypi-kernel ]; then
  VARIANT="raspi"
fi

# Find latest release tag (fallback to a known-good)
TAG="$(curl -fsSL https://api.github.com/repos/ayufan/camera-streamer/releases/latest \
       | grep -m1 '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/')" || true
[ -n "$TAG" ] || TAG="0.2.7"

PKG="camera-streamer-${VARIANT}_${TAG}.${CODENAME}_${ARCH}.deb"
URL="https://github.com/ayufan/camera-streamer/releases/download/v${TAG}/${PKG}"
TMP="/tmp/${PKG}"

echo_green "[camera-streamer] installing variant=${VARIANT} tag=v${TAG} arch=${ARCH} codename=${CODENAME}"

# Download (fallback to bullseye asset if bookworm missing)
if ! wget -O "$TMP" "$URL"; then
  ALT="camera-streamer-${VARIANT}_${TAG}.bullseye_${ARCH}.deb"
  ALT_URL="https://github.com/ayufan/camera-streamer/releases/download/v${TAG}/${ALT}"
  echo_red "[camera-streamer] bookworm asset not found, trying bullseye asset"
  wget -O "$TMP" "$ALT_URL"
fi

# Install .deb (apt resolves deps)
apt-get install -y "$TMP" || true

# Health check (non-fatal): binary presence, version/help
if command -v camera-streamer >/dev/null 2>&1; then
  if camera-streamer --version >/dev/null 2>&1; then
    VSN="$(camera-streamer --version 2>/dev/null | head -n1 || true)"
    echo_green "[camera-streamer] OK: ${VSN}"
  else
    echo_red "[camera-streamer] WARN: --version failed (continuing)"
  fi
  if ! camera-streamer --help >/dev/null 2>&1; then
    echo_red "[camera-streamer] WARN: --help failed (continuing)"
  fi
else
  echo_red "[camera-streamer] binary not found after install (continuing)"
fi
