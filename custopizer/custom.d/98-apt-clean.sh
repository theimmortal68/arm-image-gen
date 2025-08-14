#!/usr/bin/env bash
set -Eeuxo pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap
export DEBIAN_FRONTEND=noninteractive

apt-get clean || true
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/* || true

rm -rf /root/.cache || true
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true
[ -n "${KS_USER:-}" ] && rm -rf "/home/${KS_USER}/.cache" || true

: > /etc/machine-id
rm -f /var/lib/dbus/machine-id || true
ln -sf /etc/machine-id /var/lib/dbus/machine-id || true

find /var/log -type f -exec sh -c '> "$1"' _ {} \; || true
echo "[clean] apt caches cleared, machine-id normalized, logs truncated"
