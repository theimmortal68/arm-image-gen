#!/usr/bin/env bash
set -Eeuxo pipefail
export LC_ALL=C
# shellcheck disable=SC1091
source /common.sh; install_cleanup_trap
export DEBIAN_FRONTEND=noninteractive

# Only meaningful on Pi images; safe no-op otherwise
if ! grep -q 'archive.raspberrypi.com' /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
  echo "[pi-libcamera] raspberrypi.com repo not found; skipping"
  exit 0
fi

# Make sure pins are applied before we resolve dependencies
apt-get -o Acquire::Retries=3 update || true

# Install the Pi camera stack bits (names are stable across Bookworm)
# Best-effort; let apt choose exact versions according to the pin
apt-get install -y --no-install-recommends \
  libraspberrypi0 libraspberrypi-bin libcamera0 libcamera-dev v4l-utils || true

# Quick report of origins/versions (helps debug if something mixes)
echo "[pi-libcamera] apt policy (libcamera0):"
apt-cache policy libcamera0 || true
echo "[pi-libcamera] dpkg list (libcamera & libraspberrypi):"
dpkg -l | awk '/^ii/ && /(libcamera|libraspberrypi)/ {printf "[pkg] %-40s %s\n",$2,$3}' || true

echo "[pi-libcamera] sanity complete"
