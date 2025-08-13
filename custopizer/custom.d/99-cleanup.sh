#!/bin/bash
set -x
set -e
export LC_ALL=C
source /common.sh
install_cleanup_trap

# Clean apt caches & logs
apt-get clean
rm -rf /var/cache/apt/archives/* /var/lib/apt/lists/*
find /var/log -type f -name "*.log" -size +0c -exec truncate -s 0 {} +

# Optional: disable persistent journal
mkdir -p /etc/systemd/journald.conf.d
cat >/etc/systemd/journald.conf.d/99-volatile.conf <<'EOF'
[Journal]
Storage=volatile
RuntimeMaxUse=64M
EOF
