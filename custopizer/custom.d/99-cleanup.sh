#!/bin/bash
set -x
set -e
export LC_ALL=C
source /common.sh
install_cleanup_trap

apt-get clean
rm -rf /var/cache/apt/archives/* /var/lib/apt/lists/* || true
find /var/log -type f -size +0c -exec truncate -s 0 {} + || true

# Optional: volatile journal to reduce disk writes
mkdir -p /etc/systemd/journald.conf.d
cat >/etc/systemd/journald.conf.d/99-volatile.conf <<'EOF'
[Journal]
Storage=volatile
RuntimeMaxUse=64M
EOF

echo_green "[cleanup] done"
