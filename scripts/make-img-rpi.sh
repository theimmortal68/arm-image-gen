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

ROOT_KB=$(du -s -k "$ROOTFS" | awk '{print $1}')
IMG_MB=$(( (ROOT_KB*12/10)/1024 + BOOT_MB + 512 ))

echo "[make-img-rpi] Creating image ${IMG} (~${IMG_MB}MB)"
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
sudo rsync -aHAX --info=progress2 "$ROOTFS"/ "$ROOTMNT"/

sudo mount "${LOOP}p1" "$BOOTMNT"
if [ -d "$ROOTMNT/boot/firmware" ]; then
  sudo rsync -aHAX "$ROOTMNT/boot/firmware"/ "$BOOTMNT"/
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
