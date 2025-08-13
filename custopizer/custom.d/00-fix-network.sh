#!/bin/bash
set -x
set -e
export LC_ALL=C
source /common.sh; install_cleanup_trap

# If resolv.conf is a stub symlink or empty, replace it with static servers
ORIG_TARGET=""
if [ -L /etc/resolv.conf ]; then
  ORIG_TARGET="$(readlink -f /etc/resolv.conf || true)"
  rm -f /etc/resolv.conf
elif [ ! -s /etc/resolv.conf ]; then
  rm -f /etc/resolv.conf || true
fi

printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\nnameserver 1.1.1.1\n' >/etc/resolv.conf

# Quick resolution test so we fail early if DNS still broken
getent hosts deb.debian.org >/dev/null 2>&1 \
  || getent hosts archive.raspberrypi.com >/dev/null 2>&1 \
  || { echo_red "[net] DNS still broken"; cat /etc/resolv.conf || true; exit 1; }

# (Optional) record what we replaced so you can restore it later
[ -n "$ORIG_TARGET" ] && echo "$ORIG_TARGET" >/etc/.resolvconf-original || true
