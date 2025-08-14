#!/usr/bin/env bash
set -euo pipefail

ROOTFS_DIR="${1:?usage: $0 <rootfs_dir> <output_img>}"
IMG="${2:?usage: $0 <rootfs_dir> <output_img>}"

BOOT_SIZE_MB=256       # boot FAT32
IMG_SIZE_MB=2048       # base size; CustoPiZer will enlarge later
SECTOR_SIZE=512
BOOT_START_SECT=$(( 16 * 1024 * 1024 / SECTOR_SIZE ))   # 16MiB => 32768
BOOT_SIZE_SECT=$(( BOOT_SIZE_MB * 1024 * 1024 / SECTOR_SIZE ))
ROOT_START_SECT=$(( BOOT_START_SECT + BOOT_SIZE_SECT ))

echo "[make-img-rpi] Creating image ${IMG} (~${IMG_SIZE_MB}MB)"
mkdir -p "$(dirname "$IMG")"
rm -f "$IMG"
truncate -s "${IMG_SIZE_MB}M" "$IMG"

# Partition with sfdisk (no 'device:' header -> avoids 'unsupported command')
sfdisk "$IMG" <<SFDISK
label: dos
unit: sectors

start=${BOOT_START_SECT}, size=${BOOT_SIZE_SECT}, type=c
start=${ROOT_START_SECT}, type=83
SFDISK

# Map partitions
LOOP="$(sudo losetup -P --show -f "$IMG")"
cleanup() { sudo sync; sudo umount -R /mnt/imgroot 2>/dev/null || true; sudo losetup -d "$LOOP" 2>/dev/null || true; }
trap cleanup EXIT

# Create filesystems
sudo mkfs.vfat -F 32 -n BOOT "${LOOP}p1"
sudo mkfs.ext4 -F -L rootfs "${LOOP}p2"

# Mount and copy
sudo mkdir -p /mnt/imgroot
sudo mount "${LOOP}p2" /mnt/imgroot
sudo mkdir -p /mnt/imgroot/boot/firmware
sudo mount "${LOOP}p1" /mnt/imgroot/boot/firmware

# Copy rootfs (preserve numeric ids; be permissive with ownership if needed)
sudo rsync -aHAX --numeric-ids --inplace \
  --info=progress2 \
  --exclude='/dev/*' --exclude='/proc/*' --exclude='/sys/*' --exclude='/tmp/*' \
  --exclude='/run/*' --exclude='/mnt/*' --exclude='/media/*' --exclude='/lost+found' \
  "$ROOTFS_DIR"/ /mnt/imgroot/

# Ensure boot files exist (your bdebstrap layer writes these already)
sudo sync
echo "[make-img-rpi] Image ready at ${IMG}"
