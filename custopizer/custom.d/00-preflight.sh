#!/usr/bin/env bash
set -Eeuxo pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap

# --- Context (diagnostics only)
echo "[preflight] arch: $(uname -m)"
dpkg --print-architecture || true
echo "[preflight] user: $(id -un) uid=$(id -u)"

echo "[preflight] resolv.conf:"
cat /etc/resolv.conf || true
getent hosts deb.debian.org || true

# --- Clock metadata to avoid "Release file not yet valid"
[ -e /etc/localtime ] || ln -sf /usr/share/zoneinfo/UTC /etc/localtime
[ -e /etc/timezone ]  || echo "UTC" > /etc/timezone

# --- DNS parachute (no-op unless stub detected)
if grep -q '127\.0\.0\.53' /etc/resolv.conf 2>/dev/null; then
  # keep a one-time backup so 97-dns-restore can put it back
  [ -f /etc/resolv.conf.preflight.bak ] || cp -f /etc/resolv.conf /etc.resolv.conf.preflight.bak || true
  cat > /etc/resolv.conf <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
options timeout:3 attempts:2 rotate
EOF
  echo "[preflight] dns-guard: replaced stub resolv.conf"
else
  echo "[preflight] dns-guard: resolv.conf looks fine; no changes"
fi

# --- Minimal apt probe (best-effort; never break the build)
export DEBIAN_FRONTEND=noninteractive
apt-get -o Acquire::Retries=3 update || true
apt-get -y -o Dpkg::Options::=--force-confnew install ca-certificates curl gnupg || true

echo "[preflight] done"
