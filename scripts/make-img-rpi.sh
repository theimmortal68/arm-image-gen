#!/usr/bin/env bash
# Create a bootable RPi image (MBR: p1 FAT32 /boot/firmware, p2 ext4 /)
# Kernel args merge supports ARG_STRATEGY:
#   - append  (default): keep existing values; add new keys from EXTRA_APPEND
#   - replace: replace existing keys with values from EXTRA_APPEND
set -euo pipefail

ROOTFS="${1:?usage: $0 /path/to/rootfs}"
IMG="${2:-build/input-rpi64.img}"
BOOT_MB="${BOOT_MB:-512}"
if [ ! -d "$ROOTFS" ]; then
  echo "[make-img-rpi] ERROR: rootfs not found at: $ROOTFS"
  echo "Build it first: DEVICE=rpi64 bash scripts/build-device.sh"
  exit 1
fi
ARG_STRATEGY="${ARG_STRATEGY:-append}"  # append | replace

sudo mkdir -p "$(dirname "$IMG")"

# after
ROOT_KB=$(sudo du -sk "$ROOTFS" 2>/dev/null | awk '{print $1}')
if ! [[ "$ROOT_KB" =~ ^[0-9]+$ ]]; then
  echo "[make-img-opi5] WARN: du size detection failed; using 800000 KB fallback"
  ROOT_KB=800000
fi
IMG_MB=$(( (ROOT_KB*12/10)/1024 + BOOT_MB + 512 ))

# Build dir must be writable by the current user
BUILDDIR="$(dirname "$IMG")"
mkdir -p "$BUILDDIR"
# If someone created it with sudo earlier, take ownership back
if [ ! -w "$BUILDDIR" ]; then
  sudo chown "$(id -u)":"$(id -g)" "$BUILDDIR"
fi

echo "[make-img-$(basename "$0" .sh)] Creating image ${IMG} (~${IMG_MB}MB)"
truncate -s "${IMG_MB}M" "$IMG"

parted -s "$IMG" mklabel msdos
parted -s "$IMG" mkpart primary fat32 1MiB $((1+BOOT_MB))MiB
parted -s "$IMG" mkpart primary ext4 $((1+BOOT_MB))MiB 100%

LOOP=$(sudo losetup -Pf --show "$IMG")
echo "[make-img-rpi] LOOP=${LOOP}"

sudo mkfs.vfat -F32 -n boot "${LOOP}p1"
sudo mkfs.ext4 -F -L rootfs "${LOOP}p2"

BOOTMNT=$(mktemp -d)
ROOTMNT=$(mktemp -d)
sudo mount "${LOOP}p2" "$ROOTMNT"
# BEFORE:
# sudo rsync -aHAX --info=progress2 "$ROOTFS"/ "$ROOTMNT"/

# AFTER: preserve attrs, but force root:root ownership in the image
sudo rsync -aHAX --numeric-ids --chown=0:0 --info=progress2 "$ROOTFS"/ "$ROOTMNT"/

# Ensure sudo is owned by root and setuid (belt & suspenders)
if [ -f "$ROOTMNT/usr/bin/sudo" ]; then
  sudo chown 0:0 "$ROOTMNT/usr/bin/sudo"
  sudo chmod 4755 "$ROOTMNT/usr/bin/sudo"
fi

# --- PolicyKit shim for Bookworm: install polkitd and mark policykit-1 as installed ---
# This avoids CustoPiZer failing on 'apt-get install policykit-1'
sudo chroot "$ROOTMNT" bash -euo pipefail <<'EOSH'
set -e
export DEBIAN_FRONTEND=noninteractive

# Make sure we can resolve names inside the chroot if not already fixed externally
if ! grep -q 'nameserver' /etc/resolv.conf 2>/dev/null; then
  printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf
fi

# Install the real daemon (best effort)
apt-get update || true
apt-get install -y polkitd || true

# If 'policykit-1' is not in the dpkg database, create a tiny dummy package so APT
# thinks it's satisfied when CustoPiZer tries to install it.
if ! dpkg -s policykit-1 >/dev/null 2>&1; then
  ARCH="$(dpkg --print-architecture)"
  mkdir -p /tmp/pk1/DEBIAN
  cat > /tmp/pk1/DEBIAN/control <<EOF
Package: policykit-1
Version: 1:9999
Section: admin
Priority: optional
Architecture: ${ARCH}
Maintainer: local <local@localhost>
Description: Dummy policykit-1 to satisfy CustoPiZer on Debian Bookworm
Provides: policykit-1
EOF
  dpkg-deb --build /tmp/pk1 /tmp/policykit-1_1%3a9999_${ARCH}.deb
  dpkg -i /tmp/policykit-1_1%3a9999_${ARCH}.deb
fi
EOSH

sudo mount "${LOOP}p1" "$BOOTMNT"
if [ -d "$ROOTMNT/boot/firmware" ]; then
  # FAT32 doesn't support chown/perms; avoid -a
  sudo rsync -rltD --delete --no-owner --no-group --no-perms \
    "$ROOTMNT/boot/firmware"/ "$BOOTMNT"/
fi

# Merge EXTRA_APPEND into cmdline.txt (idempotent; strategy-controlled)
if [ -n "${EXTRA_APPEND:-}" ]; then
  if [ ! -f "$BOOTMNT/cmdline.txt" ]; then
    echo "console=serial0,115200 console=tty1 root=PARTUUID=00000000-02 rootfstype=ext4 fsck.repair=yes rootwait" | sudo tee "$BOOTMNT/cmdline.txt" >/dev/null
  fi
  CURRENT="$(tr '\n' ' ' < "$BOOTMNT/cmdline.txt" | tr -s ' ')"
  declare -A final seen
  base_order=()

  # Parse existing tokens
  for tok in $CURRENT; do
    key="${tok%%=*}"
    if [[ -z "${seen[$key]:-}" ]]; then
      base_order+=("$key")
    fi
    seen["$key"]=1
    final["$key"]="$tok"
  done

  # Apply extras
  for tok in $EXTRA_APPEND; do
    [ -z "$tok" ] && continue
    key="${tok%%=*}"
    if [[ "$ARG_STRATEGY" == "replace" ]]; then
      # Replace existing value or add new key
      final["$key"]="$tok"
      if [[ -z "${seen[$key]:-}" ]]; then base_order+=("$key"); fi
      seen["$key"]=1
    else
      # append strategy: only add if key does not exist
      if [[ -z "${seen[$key]:-}" ]]
      then
        final["$key"]="$tok"; base_order+=("$key"); seen["$key"]=1
      fi
    fi
  done

  NEW=""
  for key in "${base_order[@]}"; do
    tok="${final[$key]}"
    [ -n "$tok" ] && NEW+="$tok "
  done
  NEW="${NEW%% }"

  echo "$NEW" | sudo tee "$BOOTMNT/cmdline.txt" >/dev/null
  echo "[make-img-rpi] cmdline.txt merged with strategy=${ARG_STRATEGY}"
fi

BOOT_UUID=$(sudo blkid -s UUID -o value "${LOOP}p1")
ROOT_UUID=$(sudo blkid -s UUID -o value "${LOOP}p2")
sudo tee "$ROOTMNT/etc/fstab" >/dev/null <<EOF
UUID=${ROOT_UUID}  /              ext4  defaults,noatime  0 1
UUID=${BOOT_UUID}  /boot/firmware vfat  defaults,noatime  0 2
EOF

sync
sudo umount "$BOOTMNT" || true
sudo umount "$ROOTMNT" || true
sudo losetup -d "$LOOP" || true
rmdir "$BOOTMNT" "$ROOTMNT"

echo "[make-img-rpi] Done -> $IMG"
