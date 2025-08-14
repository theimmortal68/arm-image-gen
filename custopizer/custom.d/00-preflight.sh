#!/usr/bin/env bash
set -euox pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap

echo "[preflight] arch: $(uname -m)  dpkg-arch: $(dpkg --print-architecture || true)"
echo "[preflight] PATH: $PATH"
echo "[preflight] whoami: $(whoami)"

# Ensure critical mounts in chroot
for mnt in proc sys dev dev/pts run; do
  if ! mountpoint -q "/$mnt"; then
    case "$mnt" in
      proc)    mount -t proc proc /proc ;;
      sys)     mount -t sysfs sysfs /sys ;;
      dev)     mount -t devtmpfs devtmpfs /dev || mount --bind /dev /dev ;;
      dev/pts) mkdir -p /dev/pts; mount -t devpts devpts /dev/pts ;;
      run)     mount -t tmpfs tmpfs /run ;;
    esac
    echo "[preflight] mounted /$mnt"
  fi
done

# Clock sanity helps with apt (Release file not yet valid)
if [ ! -e /etc/localtime ] && [ -e /usr/share/zoneinfo/UTC ]; then
  ln -sf /usr/share/zoneinfo/UTC /etc/localtime
fi
[ -e /etc/timezone ] || echo "UTC" > /etc/timezone

# DNS sanity
echo "[preflight] resolv.conf:"
cat /etc/resolv.conf || true
getent hosts deb.debian.org || true
getent hosts archive.raspberrypi.org || true

# Minimal apt probe
export DEBIAN_FRONTEND=noninteractive
apt-get -o Acquire::Retries=3 update
apt-get -y -o Dpkg::Options::=--force-confnew install ca-certificates curl gnupg
