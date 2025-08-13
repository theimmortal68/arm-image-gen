#!/bin/bash
set -x
set -e

export LC_ALL=C

source /common.sh
install_cleanup_trap

echo "[DNS-FIX] forcing resolv.conf + apt IPv4"
rm -f /etc/resolv.conf || true
printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\nnameserver 1.1.1.1\n' >/etc/resolv.conf

cat >/etc/apt/apt.conf.d/99net-tuning <<'EOF'
Acquire::ForceIPv4 "true";
Acquire::Retries "5";
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
EOF

# Ensure Bookworm sources exist (main+contrib+non-free+non-free-firmware)
if ! grep -qE '^deb .*bookworm' /etc/apt/sources.list 2>/dev/null; then
  cat >/etc/apt/sources.list <<'EOF'
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
EOF
fi

# Sanity: glibc NSS must have the DNS plugin available
if ! ldconfig -p | grep -q 'libnss_dns.so.2'; then
  echo "[DNS-FIX] ERROR: libnss-dns missing in chroot; bake it into the base rootfs."
  exit 1
fi

# Make sure nsswitch will consult DNS
if ! grep -qE '^hosts:.*\bdns\b' /etc/nsswitch.conf 2>/dev/null; then
  sed -i 's/^hosts:.*/hosts: files dns myhostname/' /etc/nsswitch.conf || true
fi

# Try update with retries
i=0
until apt-get update; do
  i=$((i+1)); [ "$i" -ge 5 ] && exit 1
  sleep 5
done

getent hosts deb.debian.org || true
