#!/usr/bin/env bash
# scripts/make-img-rpi.sh
# Usage: scripts/make-img-rpi.sh <ROOTFS_DIR> <OUTPUT_IMG> [SIZE_MB]
#
# - Creates an MBR image with:
#     p1: FAT32 @ 16MiB offset, 256MiB size  -> /boot/firmware
#     p2: ext4 (rest of disk)                -> /
# - Copies ROOTFS into the image.
#   * Root (ext4): full fidelity (owners, links, xattrs/ACLs if available).
#   * Boot (vfat): no owner/group preserve (VFAT doesn’t support Unix owners).
#
# Env knobs:
#   ENLARGEROOT=<MiB>  Headroom added to auto-computed size (default 1200)

set -euo pipefail

# ---------- Args ----------
ROOTFS_DIR="${1:?usage: $0 <ROOTFS_DIR> <OUTPUT_IMG> [SIZE_MB]}"
OUTPUT_IMG="${2:?usage: $0 <ROOTFS_DIR> <OUTPUT_IMG> [SIZE_MB]}"
SIZE_MB="${3:-}"   # optional

# ---------- Helpers ----------
die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing required tool: $1"; }

SUDO=()
[[ $EUID -ne 0 ]] && SUDO=(sudo)

# Disable ext4 journal only when appropriate; warn (don’t fail) on tuning errors.
disable_ext4_journal() {
  local dev="$1"

  # Confirm filesystem type
  local fstype
  fstype="$("${SUDO[@]}" blkid -o value -s TYPE "$dev" 2>/dev/null || true)"
  if [[ "$fstype" != "ext4" ]]; then
    echo "[fs] $dev is '$fstype' (not ext4); skipping journal tweak."
    return 0
  fi

  # Check if journal is present
  if "${SUDO[@]}" tune2fs -l "$dev" 2>/dev/null | grep -q 'has_journal'; then
    echo "[fs] Disabling ext4 journal on $dev…"
    if ! "${SUDO[@]}" tune2fs -O ^has_journal "$dev"; then
      echo "[fs] WARNING: tune2fs failed on $dev; leaving journal enabled."
      return 0
    fi
    echo "[fs] Journal disabled on $dev."
  else
    echo "[fs] Journal already disabled on $dev; nothing to do."
  fi
}

# ---------- Required host tools ----------
need truncate; need sfdisk; need losetup; need mkfs.vfat; need mkfs.ext4
need partprobe; need rsync; need awk; need grep; need sed; need tune2fs
need blkid; need udevadm

[[ -d "$ROOTFS_DIR" ]] || die "ROOTFS_DIR not found: $ROOTFS_DIR"
[[ -n "$(ls -A "$ROOTFS_DIR" 2>/dev/null || true)" ]] || die "ROOTFS_DIR is empty: $ROOTFS_DIR"

# ---------- Compute size ----------
if [[ -z "$SIZE_MB" ]]; then
  # MiB apparent size of the rootfs (ignore permission warnings)
  ROOT_MB=$(du -s -B1M --apparent-size "$ROOTFS_DIR" 2>/dev/null | awk '{print $1}')
  [[ -n "$ROOT_MB" ]] || ROOT_MB=800
  HEADROOM="${ENLARGEROOT:-1200}"
  SIZE_MB=$(( ROOT_MB + HEADROOM ))
  (( SIZE_MB < 2048 )) && SIZE_MB=2048
fi

BOOT_SIZE_MB=256                 # FAT32 boot partition size
SECTOR_SIZE=512
BOOT_START_SECT=$(( 16 * 1024 * 1024 / SECTOR_SIZE ))   # 16MiB -> 32768
BOOT_SIZE_SECT=$(( BOOT_SIZE_MB * 1024 * 1024 / SECTOR_SIZE ))
ROOT_START_SECT=$(( BOOT_START_SECT + BOOT_SIZE_SECT ))

echo "[make-img-rpi] Creating ${OUTPUT_IMG} (~${SIZE_MB}MB)"
mkdir -p "$(dirname "$OUTPUT_IMG")"
rm -f "$OUTPUT_IMG"
# Prefer truncate; fall back to dd if FS blocks it
if ! truncate -s "${SIZE_MB}M" "$OUTPUT_IMG" 2>/dev/null; then
  "${SUDO[@]}" dd if=/dev/zero of="$OUTPUT_IMG" bs=1M count="$SIZE_MB" status=progress
fi

# ---------- Partition (MBR) ----------
# Note: no 'device:' header (older sfdisk rejects it). Units: sectors.
sfdisk "$OUTPUT_IMG" <<SFDISK
label: dos
unit: sectors

start=${BOOT_START_SECT}, size=${BOOT_SIZE_SECT}, type=c, bootable
start=${ROOT_START_SECT}, type=83
SFDISK

# ---------- Loop setup ----------
"${SUDO[@]}" modprobe loop || true
LOOPDEV="$("${SUDO[@]}" losetup -P --show -f "$OUTPUT_IMG")" || die "losetup failed"
echo "[make-img-rpi] Loop device: $LOOPDEV"
"${SUDO[@]}" partprobe "$LOOPDEV" || true
sleep 1
"${SUDO[@]}" udevadm settle || true

BOOT_PART="${LOOPDEV}p1"
ROOT_PART="${LOOPDEV}p2"
[[ -b "$BOOT_PART" ]] || die "Boot partition node missing: $BOOT_PART"
[[ -b "$ROOT_PART" ]] || die "Root partition node missing: $ROOT_PART"

# ---------- Make filesystems ----------
"${SUDO[@]}" mkfs.vfat -F 32 -n BOOT "$BOOT_PART"
"${SUDO[@]}" mkfs.ext4 -F -L rootfs "$ROOT_PART"

# Toggle ext4 journaling *only* when safe/appropriate (don’t mask other errors)
disable_ext4_journal "$ROOT_PART"

# ---------- Mount (ROOT first, then BOOT inside it) ----------
MNT="$(mktemp -d)"
cleanup() {
  set +e
  sync
  "${SUDO[@]}" umount "$MNT/boot/firmware" 2>/dev/null || true
  "${SUDO[@]}" umount "$MNT" 2>/dev/null || true
  "${SUDO[@]}" losetup -d "$LOOPDEV" 2>/dev/null || true
  rmdir "$MNT" 2>/dev/null || true
}
trap cleanup EXIT

"${SUDO[@]}" mount "$ROOT_PART" "$MNT"
"${SUDO[@]}" install -d "$MNT/boot/firmware"
"${SUDO[@]}" mount "$BOOT_PART" "$MNT/boot/firmware"

# ---------- Copy rootfs (EXT4) ----------
# Exclude boot/firmware so we can sync it separately to VFAT.
if ! "${SUDO[@]}" rsync -aHAX --numeric-ids --delete \
  --exclude='/dev/*' --exclude='/proc/*' --exclude='/sys/*' \
  --exclude='/run/*' --exclude='/tmp/*' --exclude='/mnt/*' \
  --exclude='/media/*' --exclude='/lost+found' \
  --exclude='/boot/firmware/*' \
  "$ROOTFS_DIR"/ "$MNT"/; then
  echo "[rsync] Falling back without xattrs/ACLs…"
  "${SUDO[@]}" rsync -rltD --numeric-ids --delete \
    --exclude='/dev/*' --exclude='/proc/*' --exclude='/sys/*' \
    --exclude='/run/*' --exclude='/tmp/*' --exclude='/mnt/*' \
    --exclude='/media/*' --exclude='/lost+found' \
    --exclude='/boot/firmware/*' \
    "$ROOTFS_DIR"/ "$MNT"/
fi

# Ensure temp dirs exist with correct perms
"${SUDO[@]}" install -d -m 1777 "$MNT/tmp" "$MNT/var/tmp"

# ---------- Copy boot/firmware (VFAT) ----------
if [[ -d "$ROOTFS_DIR/boot/firmware" ]]; then
  "${SUDO[@]}" rsync -rlt --delete --no-owner --no-group \
    --chmod=Du+rwX,Fu+rw,Da+rx,Fa+rX \
    "$ROOTFS_DIR/boot/firmware/"/ "$MNT/boot/firmware/"/
fi

# ---------- Ensure basic boot files if missing ----------
if ! [[ -s "$MNT/boot/firmware/config.txt" ]]; then
  cat <<'EOF' | "${SUDO[@]}" tee "$MNT/boot/firmware/config.txt" >/dev/null
arm_64bit=1
enable_uart=1
hdmi_force_hotplug=1
dtoverlay=vc4-kms-v3d
EOF
fi

if ! [[ -s "$MNT/boot/firmware/cmdline.txt" ]]; then
  cat <<'EOF' | "${SUDO[@]}" tee "$MNT/boot/firmware/cmdline.txt" >/dev/null
console=serial0,115200 console=tty1 root=LABEL=rootfs rootfstype=ext4 fsck.repair=yes rootwait
EOF
fi

sync
echo "[make-img-rpi] Done: $OUTPUT_IMG"
