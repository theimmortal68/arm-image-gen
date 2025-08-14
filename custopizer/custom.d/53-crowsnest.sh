#!/usr/bin/env bash
set -Eeuxo pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap
export DEBIAN_FRONTEND=noninteractive

CONF="/etc/crowsnest.conf"
[ -f "$CONF" ] && echo "[crowsnest] using $CONF" || echo "[crowsnest] no staged config; using defaults"

# Runtime sanity (soft checks)
if command -v camera-streamer >/dev/null 2>&1; then
  echo "[crowsnest] camera-streamer: $(camera-streamer --version 2>/dev/null | head -n1 || true)"
  ldd "$(command -v camera-streamer)" | awk '/=>/ {print "[ldd] " $0}' || true
else
  echo "[crowsnest] WARN: camera-streamer not in PATH (OK if using another streamer)"
fi

v4l2-ctl --version 2>/dev/null || echo "[crowsnest] WARN: v4l-utils not present (OK in chroot)"

echo "[crowsnest] done"
