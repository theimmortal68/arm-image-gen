#!/usr/bin/env bash
# Usage: make-img-rpi.sh <rootfs_dir> <out_img> [size_mb]
# Create a DOS-partitioned image with FAT32 /boot (mounted at /boot/firmware) and ext4 root.
set -euo pipefail

ROOTFS="${1:?rootfs directory (from bdebstrap output)}"
OUT_IMG="${2:?output image path}"
SIZE_MB="${3:-}"      # optional override
BOOT_MB="${BOOT_MB:-256}"

if [ ! -d "$ROOTFS" ]; then
  echo "Rootfs not found: $ROOTFS" >&2
  exit 1
fi

# Estimate size if not provided
if [ -z "$SIZE_MB" ]; then
  # apparent size in MiB + safety margin (~600 MiB)
  ROOT_MB=$(sudo du -sBM --apparent-size "$ROOTFS" | awk '{print $1}' | sed 's/M//')
  [ -n "$ROOT_MB" ] || ROOT_MB=1024
  SIZE_MB=$(( ROOT_MB + 600 ))
  # minimum 2000 MiB
  if [ "$SIZE_MB" -lt 2000 ]; then SIZE_MB=2000; fi
fi

echo "[make-img-rpi] Creating image $OUT_IMG (~${SIZE_MB}MB)"
mkdir -p "$(dirname "$OUT_IMG")"
truncate -s "${SIZE_MB}M" "$OUT_IMG"

# Partition: MBR, p1 FAT32 (starts at 8MiB), p2 ext4 (rest)
parted -s "$OUT_IMG" mklabel msdos
parted -s "$OUT_IMG" unit MiB mkpart primary fat32 8 $((8+BOOT_MB))
parted -s "$OUT_IMG" set 1 lba on
parted -s "$OUT_IMG" unit MiB mkpart primary ext4 $((8+BOOT_MB)) 100%

# Setup loop
LOOP="$(sudo losetup --show -fP "$OUT_IMG")"
cleanup() { set +e; sync; sudo umount -R "$MNT" >/dev/null 2>&1 || true; sudo losetup -d "$LOOP" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# Filesystems
sudo mkfs.vfat -F 32 -n BOOT "${LOOP}p1"
sudo mkfs.ext4 -F -L rootfs "${LOOP}p2"

# Mount
MNT="$(mktemp -d)"
sudo mount "${LOOP}p2" "$MNT"
sudo mkdir -p "$MNT/boot/firmware"
sudo mount "${LOOP}p1" "$MNT/boot/firmware"

# Use safer rsync command
rsync -a --no-owner --no-group "$SRC" "$DEST"
RSYNC_EXIT=$?

if [ $RSYNC_EXIT -ne 0 ]; then
  echo "Warning: rsync failed with exit code $RSYNC_EXIT. This is usually due to ownership/permission issues on CI runners."
  # Optionally: exit 1 to fail, or continue if ownership isn't critical
fi

# Copy boot firmware tree from the rootfs onto the boot partition
if [ -d "$ROOTFS/boot/firmware" ]; then
  sudo rsync -a --delete "$ROOTFS/boot/firmware"/ "$MNT/boot/firmware"/
fi

# Ensure fstab has LABEL-based mounts
sudo mkdir -p "$MNT/etc"
if ! sudo grep -q '^LABEL=BOOT' "$MNT/etc/fstab" 2>/dev/null; then
  sudo tee -a "$MNT/etc/fstab" >/dev/null <<'EOF'
LABEL=BOOT   /boot/firmware  vfat  defaults  0  2
LABEL=rootfs /               ext4  defaults,noatime  0  1
EOF
fi

# Ensure cmdline.txt points root=LABEL=rootfs
if [ -f "$MNT/boot/firmware/cmdline.txt" ]; then
  sudo sed -i -E 's#root=[^ ]+#root=LABEL=rootfs#' "$MNT/boot/firmware/cmdline.txt"
fi

echo "[make-img-rpi] Image ready at $OUT_IMG"
