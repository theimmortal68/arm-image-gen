#!/usr/bin/env bash
# make-img-rpi.sh
# Usage: scripts/make-img-rpi.sh <ROOTFS_DIR> <OUTPUT_IMG> [SIZE_MB]
#
# Builds a bootable Raspberry Pi image from a directory rootfs.
# - Creates MBR with two partitions: p1 FAT32 (/boot/firmware), p2 ext4 (/)
# - Copies ROOTFS into the image with a permissive rsync strategy.

set -euo pipefail

ROOTFS_DIR="${1:?path to rootfs dir (e.g. out/rpi64-bookworm-arm64/rootfs)}"
OUTPUT_IMG="${2:?output image path (e.g. build/input-rpi64.img)}"
SIZE_MB="${3:-}"

# ---------- Helpers ----------
die() { echo "ERROR: $*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required tool: $1"
}

SUDO=()
if [[ $EUID -ne 0 ]]; then
  SUDO=(sudo)
fi

# Permissive rsync: preserve as much as we can, but don't fail the build for chown/perm issues
rsync_rootfs() {
  local src="$1" dst="$2"

  local base_flags=( -aHAXS --delete --numeric-ids --info=progress2,name0 )
  local excludes=(
    --exclude='/dev/*' --exclude='/proc/*' --exclude='/sys/*'
    --exclude='/run/*' --exclude='/tmp/*'  --exclude='/mnt/*'
    --exclude='/media/*' --exclude='/lost+found'
  )

  # First attempt: preserve owners/groups if possible
  if "${SUDO[@]}" rsync "${base_flags[@]}" "${excludes[@]}" "$src"/ "$dst"/; then
    :
  else
    echo "[rsync] retrying without owner/group preservation..."
    "${SUDO[@]}" rsync "${base_flags[@]}" --no-owner --no-group --omit-dir-times \
      "${excludes[@]}" "$src"/ "$dst"/
  fi

  # Ensure temp dirs exist and have correct perms
  "${SUDO[@]}" install -d -m 1777 "$dst/tmp" "$dst/var/tmp"
}

# ---------- Checks ----------
need truncate; need sfdisk; need losetup; need partprobe
need mkfs.vfat; need mkfs.ext4; need tune2fs; need e2label; need rsync
[[ -d "$ROOTFS_DIR" ]] || die "ROOTFS_DIR not found: $ROOTFS_DIR"

# Compute size if not provided: rootfs size + headroom (MiB), min 2048MiB
if [[ -z "${SIZE_MB}" ]]; then
  # Use du -s -B1M for portable MiB counting; ignore permission errors
  ROOT_MB=$(du -s -B1M --apparent-size "$ROOTFS_DIR" 2>/dev/null | awk '{print $1}')
  [[ -n "${ROOT_MB}" ]] || ROOT_MB=800
  # Add headroom (1200MiB) by default; you can override via ENLARGEROOT env
  HEADROOM="${ENLARGEROOT:-1200}"
  SIZE_MB=$(( ROOT_MB + HEADROOM ))
  # enforce minimum 2048MiB
  if (( SIZE_MB < 2048 )); then SIZE_MB=2048; fi
fi

BOOT_MB=256                                # FAT32 boot size
ROOT_MB=$(( SIZE_MB - BOOT_MB ))

echo "[make-img-rpi] Creating image ${OUTPUT_IMG} (~${SIZE_MB}MB)"
mkdir -p "$(dirname "$OUTPUT_IMG")"

# Create empty image
: >"$OUTPUT_IMG" || true
if ! truncate -s "${SIZE_MB}M" "$OUTPUT_IMG" 2>/dev/null; then
  # Fallback via dd if truncate blocked by FS perms
  "${SUDO[@]}" dd if=/dev/zero of="$OUTPUT_IMG" bs=1M count="$SIZE_MB" status=progress
fi

# Partition: MBR, p1 (FAT32) starting at 8MiB, p2 rest
sfdisk_script=$(cat <<EOF
label: dos
unit: MiB

# 8MiB offset for alignment
8,${BOOT_MB},c,*
$((8 + BOOT_MB)),$ROOT_MB,83
EOF
)
echo "$sfdisk_script" | "${SUDO[@]}" sfdisk "$OUTPUT_IMG"

# Map loop
LOOPDEV="$("${SUDO[@]}" losetup --find --show --partscan "$OUTPUT_IMG")"
echo "[make-img-rpi] Loop device: $LOOPDEV"
sleep 1
"${SUDO[@]}" partprobe "$LOOPDEV"

BOOT_PART="${LOOPDEV}p1"
ROOT_PART="${LOOPDEV}p2"

# Filesystems
"${SUDO[@]}" mkfs.vfat -F 32 -n bootfs "$BOOT_PART"
"${SUDO[@]}" mkfs.ext4 -F -L rootfs "$ROOT_PART"
"${SUDO[@]}" tune2fs -O ^has_journal "$ROOT_PART" || true

# Mount
MNT="$(mktemp -d)"
BOOT="$MNT/boot/firmware"
"${SUDO[@]}" install -d "$BOOT"
"${SUDO[@]}" mount "$ROOT_PART" "$MNT"
"${SUDO[@]}" mount "$BOOT_PART" "$BOOT"

cleanup() {
  set +e
  sync
  "${SUDO[@]}" umount "$BOOT" 2>/dev/null || true
  "${SUDO[@]}" umount "$MNT" 2>/dev/null || true
  "${SUDO[@]}" losetup -d "$LOOPDEV" 2>/dev/null || true
  rmdir "$MNT" 2>/dev/null || true
}
trap cleanup EXIT

# Copy rootfs -> image (permissive rsync)
echo "[make-img-rpi] Syncing rootfs to image..."
rsync_rootfs "$ROOTFS_DIR" "$MNT"

# Ensure boot files exist (config.txt/cmdline.txt may have been created by earlier layer)
if ! [[ -s "$BOOT/config.txt" ]]; then
  cat <<'EOF' | "${SUDO[@]}" tee "$BOOT/config.txt" >/dev/null
arm_64bit=1
enable_uart=1
hdmi_force_hotplug=1
dtoverlay=vc4-kms-v3d
EOF
fi
if ! [[ -s "$BOOT/cmdline.txt" ]]; then
  cat <<'EOF' | "${SUDO[@]}" tee "$BOOT/cmdline.txt" >/dev/null
console=serial0,115200 console=tty1 root=LABEL=rootfs rootfstype=ext4 fsck.repair=yes rootwait
EOF
fi

# Finalize
sync
echo "[make-img-rpi] Done: $OUTPUT_IMG"