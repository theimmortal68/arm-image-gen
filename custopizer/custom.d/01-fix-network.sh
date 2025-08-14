#!/usr/bin/env bash
set -x
set -e
export LC_ALL=C
source /common.sh; install_cleanup_trap

set -euo pipefail

# Keep whatever you already do here, then add:
if ! grep -qE '(^|\s)localhost(\s|$)' /etc/hosts; then
  echo "127.0.0.1 localhost" >> /etc/hosts
  echo "::1       localhost ip6-localhost ip6-loopback" >> /etc/hosts
fi

# Ensure resolvers look sane (no systemd-resolved stub inside chroot)
if grep -q '127.0.0.53' /etc/resolv.conf; then
  cat >/etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
options timeout:3 attempts:2 rotate
EOF
fi
