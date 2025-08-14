#!/bin/bash
set -x
set -e
export LC_ALL=C
source /common.sh; install_cleanup_trap

# If KS_USER is pre-set, respect it, else detect common users, else fallback to pi
if [ -f /etc/ks-user.conf ]; then
  . /etc/ks-user.conf || true
fi

if [ -z "${KS_USER:-}" ]; then
  for u in pi armbian orangepi ubuntu debian; do
    if getent passwd "$u" >/dev/null 2>&1; then KS_USER="$u"; break; fi
  done
  KS_USER="${KS_USER:-pi}"
fi

echo "KS_USER=${KS_USER}" >/etc/ks-user.conf
echo_green "[detect-user] KS_USER=$KS_USER"
