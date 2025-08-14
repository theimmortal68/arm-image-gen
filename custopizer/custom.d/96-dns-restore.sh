#!/usr/bin/env bash
set -Eeuxo pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap

if [ -f /etc/resolv.conf.preflight.bak ]; then
  cp -f /etc/resolv.conf.preflight.bak /etc/resolv.conf
  rm -f /etc/resolv.conf.preflight.bak
  echo "[dns-restore] restored /etc/resolv.conf"
else
  echo "[dns-restore] no backup found; leaving resolv.conf as-is"
fi
