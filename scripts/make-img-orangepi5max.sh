#!/usr/bin/env bash
# Create a bootable Orange Pi 5 family (RK3588) image.
# - Supports OPi5 / OPi5 Plus / OPi5 Max via DTB auto-detection or BOARD hint.
# - Writes Rockchip bootloaders to raw image.
# - Seeds /boot/extlinux/extlinux.conf and /boot/armbianEnv.txt
# Kernel args merge supports ARG_STRATEGY:
#   - append  (default): keep base values; add new keys from EXTRA_APPEND
#   - replace: replace base keys with values from EXTRA_APPEND
set -euo pipefail

ROOTFS="${1:?usage: $0 /path/to/rootfs}"
IMG="${2:-build/input-orangepi5max.img}"
START_MB="${START_MB:-4}"
ARG_STRATEGY="${ARG_STRATEGY:-append}"  # append | replace

sudo mkdir -p "$(dirname "$IMG")"

# -------------------- Board autodetect --------------------
BOARD="${BOARD:-}"
if [ -z "${BOARD}" ]; then
  if [ -f "$ROOTFS/etc/device-id" ]; then
    DID="$(tr -d '\n' < "$ROOTFS/etc/device-id" || true)"
    case "$DID" in
      orangepi5) BOARD="orangepi5" ;;
      orangepi5plus|orangepi5-plus) BOARD="orangepi5-plus" ;;
      orangepi5max|orangepi5-max) BOARD="orangepi5-max" ;;
    esac
  fi
fi
if [ -z "${BOARD}" ]; then
  CAND="$(ls -1d "$ROOTFS"/usr/lib/u-boot/*orangepi5* 2>/dev/null | head -n1 || true)"
  case "$CAND" in
    *orangepi5-max*) BOARD="orangepi5-max" ;;
    *orangepi5-plus*) BOARD="orangepi5-plus" ;;
    *orangepi5*) BOARD="orangepi5" ;;
  esac
fi
BOARD="${BOARD:-orangepi5-max}"
echo "[make-img-opi5] Board = ${BOARD}"

# -------------------- Image layout --------------------
ROOT_KB=$(du -s -k "$ROOTFS" | awk '{print $1}')
IMG_MB=$(( (ROOT_KB*12/10)/1024 + 512 ))
echo "[make-img-opi5] Creating image ${IMG} (~${IMG_MB}MB)"
truncate -s "${IMG_MB}M" "$IMG"

parted -s "$IMG" mklabel msdos
parted -s "$IMG" mkpart primary ext4 ${START_MB}MiB 100%

LOOP=$(sudo losetup -Pf --show "$IMG")
echo "[make-img-opi5] LOOP=${LOOP}"
sudo mkfs.ext4 -F -L rootfs "${LOOP}p1"

ROOTMNT=$(mktemp -d)
sudo mount "${LOOP}p1" "$ROOTMNT"
sudo rsync -aHAX --info=progress2 "$ROOTFS"/ "$ROOTMNT"/

ROOT_UUID=$(sudo blkid -s UUID -o value "${LOOP}p1")
sudo tee "$ROOTMNT/etc/fstab" >/dev/null <<EOF
UUID=${ROOT_UUID}  /  ext4  defaults,noatime  0 1
EOF

sudo install -d "$ROOTMNT/boot"

# -------------------- Detect kernel/initrd --------------------
KERNEL_IMAGE=""
INITRD_IMAGE=""
if [ -f "$ROOTMNT/boot/Image" ]; then
  KERNEL_IMAGE="/boot/Image"
elif ls "$ROOTMNT"/boot/vmlinuz-* >/dev/null 2>&1; then
  KVER="$(basename "$(ls -1 "$ROOTMNT"/boot/vmlinuz-* | sort -V | tail -n1)")"
  KERNEL_IMAGE="/boot/${KVER}"
fi
if ls "$ROOTMNT"/boot/initrd.img-* >/dev/null 2>&1; then
  IVER="$(basename "$(ls -1 "$ROOTMNT"/boot/initrd.img-* | sort -V | tail -n1)")"
  INITRD_IMAGE="/boot/${IVER}"
elif [ -f "$ROOTMNT/boot/initrd.img" ]; then
  INITRD_IMAGE="/boot/initrd.img"
fi

# -------------------- Detect DTB --------------------
find_dtb() {
  local root="$1" patt="$2" f
  if [ -d "$root/boot/dtb" ]; then
    f="$(find "$root/boot/dtb" -type f -name "$patt" | head -n1 || true)"
    [ -n "$f" ] && { echo "$f"; return 0; }
  fi
  f="$(find "$root/usr/lib" -type f -path '*/linux-image-*/rockchip/*.dtb' -name "$patt" | head -n1 || true)"
  [ -n "$f" ] && { echo "$f"; return 0; }
  return 1
}
DTB_FILE=""
case "$BOARD" in
  orangepi5)       DTB_FILE="$(find_dtb "$ROOTMNT" "*orangepi*5*.dtb" || true)" ;;
  orangepi5-plus)  DTB_FILE="$(find_dtb "$ROOTMNT" "*orangepi*5*plus*.dtb" || true)";;
  orangepi5-max)   DTB_FILE="$(find_dtb "$ROOTMNT" "*orangepi*5*max*.dtb" || true)";;
esac
[ -z "$DTB_FILE" ] && DTB_FILE="$(find_dtb "$ROOTMNT" "*rk3588*.dtb" || true)"
if [ -n "$DTB_FILE" ] && [[ "$DTB_FILE" == "$ROOTMNT"* ]]; then
  DTB_FILE="/${DTB_FILE#"$ROOTMNT/"}"
fi

echo "[make-img-opi5] Detected:"
echo "  kernel: ${KERNEL_IMAGE:-<missing>}"
echo "  initrd: ${INITRD_IMAGE:-<missing>}"
echo "  dtb:    ${DTB_FILE:-<missing>}"

# -------------------- Build append args with strategy --------------------
KERNEL_CONSOLE="${KERNEL_CONSOLE:-console=ttyS2,1500000 console=tty1}"
EXTRA_APPEND="${EXTRA_APPEND:-}"

merge_args() {
  # Usage: merge_args "<base args>" "<extra args>" "<strategy>"
  local base="$1" extra="$2" strategy="$3"
  declare -A map seen
  local order=() tok key out=""
  # Base
  for tok in $base; do
    key="${tok%%=*}"
    if [[ -z "${seen[$key]:-}" ]]; then order+=("$key"); fi
    seen["$key"]=1
    map["$key"]="$tok"
  done
  # Extra
  for tok in $extra; do
    [ -z "$tok" ] && continue
    key="${tok%%=*}"
    if [[ "$strategy" == "replace" ]]; then
      map["$key"]="$tok"
      if [[ -z "${seen[$key]:-}" ]]; then order+=("$key"); fi
      seen["$key"]=1
    else
      if [[ -z "${seen[$key]:-}" ]]; then
        map["$key"]="$tok"; order+=("$key"); seen["$key"]=1
      fi
    fi
  done
  for key in "${order[@]}"; do
    out+="${map[$key]} "
  done
  echo "${out%% }"
}

APPEND_BASE="root=UUID=${ROOT_UUID} rootfstype=ext4 rw rootwait ${KERNEL_CONSOLE}"
APPEND_FINAL="$(merge_args "$APPEND_BASE" "$EXTRA_APPEND" "$ARG_STRATEGY")"

# -------------------- extlinux.conf --------------------
EXDIR="$ROOTMNT/boot/extlinux"
sudo install -d "$EXDIR"
EXTLINUX="$EXDIR/extlinux.conf"

INITRD_LINE=""
FDT_LINE=""
[ -n "$INITRD_IMAGE" ] && INITRD_LINE="  initrd ${INITRD_IMAGE}"
[ -n "$DTB_FILE" ] && FDT_LINE="  fdt ${DTB_FILE}"

sudo tee "$EXTLINUX" >/dev/null <<EOF
# Auto-generated by make-img-orangepi5max.sh
timeout 10
menu title Armbian (${BOARD})

label Armbian
  kernel ${KERNEL_IMAGE:-/boot/Image}
${INITRD_LINE}
${FDT_LINE}
  append ${APPEND_FINAL}
EOF

# -------------------- armbianEnv.txt --------------------
ARMENV="$ROOTMNT/boot/armbianEnv.txt"
if [ ! -f "$ARMENV" ]; then
  sudo tee "$ARMENV" >/dev/null <<'EOF'
verbosity=1
console=serial
overlays=i2c0 spi-spidev
EOF
fi

# -------------------- Bootloaders --------------------
IDB=$(sudo find "$ROOTFS/usr/lib" -type f -name 'idbloader.img' | head -n1 || true)
UBOOT=$(sudo find "$ROOTFS/usr/lib" -type f -name 'u-boot.itb' | head -n1 || true)
if [ -z "$IDB" ] || [ -z "$UBOOT" ]; then
  echo "[make-img-opi5] ERROR: idbloader.img / u-boot.itb not found under $ROOTFS/usr/lib"
  echo "Ensure linux-u-boot-orangepi5*-* is installed into the rootfs."
  exit 1
fi
echo "[make-img-opi5] Writing bootloaders"
sudo dd if="$IDB" of="$LOOP" bs=512 seek=64 conv=notrunc status=none
sudo dd if="$UBOOT" of="$LOOP" bs=512 seek=16384 conv=notrunc status=none

# -------------------- Verify & cleanup --------------------
RC=0
for f in "$EXTLINUX" "$ARMENV"; do
  if [ -s "$f" ]; then
    echo "[verify] OK: $(realpath --relative-to="$ROOTMNT" "$f")"
  else
    echo "[verify] MISSING/EMPTY: $(realpath --relative-to="$ROOTMNT" "$f")"; RC=1
  fi
done
[ -n "$KERNEL_IMAGE" ] && [ -f "$ROOTMNT${KERNEL_IMAGE}" ] || { echo "[verify] Kernel missing at ${KERNEL_IMAGE}"; RC=1; }
[ -n "$INITRD_IMAGE" ] && [ -f "$ROOTMNT${INITRD_IMAGE}" ] || echo "[verify] Note: initrd not found (may be fine)"
[ -n "$DTB_FILE" ] && [ -f "$ROOTMNT${DTB_FILE}" ] || echo "[verify] Note: DTB not found (U-Boot may still choose a default)"

sync
sudo umount "$ROOTMNT" || true
sudo losetup -d "$LOOP" || true
rmdir "$ROOTMNT"

if [ "$RC" -ne 0 ]; then
  echo "[make-img-opi5] Completed with warnings/errors (see verify output above)."
  exit "$RC"
fi
echo "[make-img-opi5] Done -> $IMG"
