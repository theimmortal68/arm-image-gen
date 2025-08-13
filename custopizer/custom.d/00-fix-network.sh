#!/bin/sh
# Runs INSIDE the chroot, before other scripts
set -eux

# Ensure DNS works
if [ -L /etc/resolv.conf ] || [ ! -s /etc/resolv.conf ]; then
  rm -f /etc/resolv.conf
  printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' >/etc/resolv.conf
fi

# Force IPv4 + sane apt retries/timeouts
cat >/etc/apt/apt.conf.d/99net-tuning <<'EOF'
Acquire::ForceIPv4 "true";
Acquire::Retries "5";
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
EOF

# Ensure Bookworm sources (main+contrib+non-free+non-free-firmware)
if ! grep -qE '^deb .*bookworm' /etc/apt/sources.list 2>/dev/null; then
  cat >/etc/apt/sources.list <<'EOF'
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
EOF
fi

# Update with retries
i=0
until apt-get update; do
  i=$((i+1)); [ "$i" -ge 5 ] && exit 1
  sleep 5
done
