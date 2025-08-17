#!/usr/bin/env bash
set -Eeuxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

# shellcheck disable=SC1091
source /common.sh; install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

section "Pi libcamera sanity"

# Only meaningful on Pi images; safe no-op otherwise
if ! grep -q 'archive.raspberrypi.com' /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
  echo "[pi-libcamera] raspberrypi.com repo not found; skipping"
  exit 0
fi

# Make sure pins are applied before we resolve dependencies
apt_update_once || true

# Install the Pi camera stack bits (names are stable across Bookworm)
apt_install libraspberrypi0 libraspberrypi-bin libcamera0 libcamera-dev v4l-utils || true

# Quick report of origins/versions (helps debug if something mixes)
echo "[pi-libcamera] apt policy (libcamera0):"
apt-cache policy libcamera0 || true
echo "[pi-libcamera] dpkg list (libcamera & libraspberrypi):"
dpkg -l | awk '/^ii/ && /(libcamera|libraspberrypi)/ {printf "[pkg] %-40s %s\n",$2,$3}' || true

echo "[pi-libcamera] sanity complete"
apt_clean_all
