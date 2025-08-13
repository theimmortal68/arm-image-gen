#!/bin/bash
set -x
set -e
export LC_ALL=C

source /common.sh
install_cleanup_trap

# Always use our persisted KS_USER if present
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true

echo_green "[netfix] forcing resolv.conf + apt IPv4 + retries"

# Replace resolv.conf with a simple static one (works in chroot)
rm -f /etc/resolv.conf || true
printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\nnameserver 1.1.1.1\n' >/etc/resolv.conf

# Make apt more resilient on CI and prefer IPv4
cat >/etc/apt/apt.conf.d/99net-tuning <<'EOF'
Acquire::ForceIPv4 "true";
Acquire::Retries "5";
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
EOF

# Ensure Debian Bookworm sources exist (idempotent)
if ! grep -qE '^deb .*bookworm' /etc/apt/sources.list 2>/dev/null; then
  cat >/etc/apt/sources.list <<'EOF'
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
EOF
fi

# Netbase provides /etc/services etc.; harmless if already present
retry 4 2 apt-get update
if is_in_apt netbase && ! is_installed netbase; then
  apt-get install -y --no-install-recommends netbase || true
fi

# Sanity: ensure glibc can resolve via DNS (libnss_dns comes from libc6 on Bookworm)
if ! ldconfig -p | grep -q 'libnss_dns.so.2'; then
  echo_red "[netfix] WARN: libnss_dns.so.2 not visible via ldconfig (usually fine on Bookworm)"
fi

# Quick smoke test (non-fatal)
getent hosts deb.debian.org || true
