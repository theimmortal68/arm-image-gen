#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh
install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

section "Restoring resolv.conf (if previously backed up)"
if [ -f /etc/resolv.conf.custopizer.bak ]; then
  mv -f /etc/resolv.conf.custopizer.bak /etc/resolv.conf || true
fi
