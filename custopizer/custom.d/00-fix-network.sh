#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh
install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

section "Fixing DNS/resolv.conf for chroot"
# Replace stub resolv.conf with host's for the duration of the build
if [ -f /etc/resolv.conf ]; then
  cp -f /etc/resolv.conf /etc/resolv.conf.custopizer.bak || true
fi
printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" | wr_root 0644 /etc/resolv.conf
