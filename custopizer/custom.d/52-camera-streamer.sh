#!/bin/bash
set -Eeuxo pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap

# Fetch helper with retries (curl preferred, wget fallback)
fetch() {
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 5 --retry-delay 2 --retry-all-errors -o "$out" "$url"
  else
    wget --tries=5 --waitretry=2 --retry-connrefused -O "$out" "$url"
  fi
}

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates wget curl jq xz-utils tar

CODENAME="$(. /etc/os-release; echo "${VERSION_CODENAME:-bookworm}")"
ARCH="$(dpkg --print-architecture)"
VARIANT="generic"
# If Raspberry Pi kernel package is present, use raspi variant
[ -e /etc/default/raspberrypi-kernel ] && VARIANT="raspi"

# Determine latest camera-streamer tag (fallback to pinned if API not reachable)
TAG_DEFAULT="0.2.8"
TAG="$TAG_DEFAULT"
if curl -fsSL "https://api.github.com/repos/ayufan/camera-streamer/releases/latest" >/tmp/cs.latest.json 2>/dev/null; then
  TAG="$(jq -r '.tag_name' /tmp/cs.latest.json | sed 's/^v//')"
  [ -n "${TAG}" ] || TAG="$TAG_DEFAULT"
fi

# Map arch -> asset suffix (primary target is arm64)
case "$ARCH" in
  arm64|aarch64) ASSET="camera-streamer_${TAG}_linux_aarch64.tar.gz" ;;
  armhf|armel|arm) ASSET="camera-streamer_${TAG}_linux_armv7.tar.gz" ;; # best-effort for 32-bit
  *) echo_red "[camera-streamer] unsupported arch: $ARCH"; exit 2 ;;
esac

URL="https://github.com/ayufan/camera-streamer/releases/download/v${TAG}/${ASSET}"
TMP="/tmp/camera-streamer-${TAG}"
BIN="/usr/local/bin/camera-streamer"

rm -rf "$TMP"
mkdir -p "$TMP"
echo_green "[camera-streamer] downloading ${URL}"
fetch "$URL" "${TMP}/cs.tgz"

# Extract & install
tar -xzf "${TMP}/cs.tgz" -C "$TMP"
# Find the binary inside the tarball (name can vary slightly)
CS_PATH="$(find "$TMP" -type f -name 'camera-streamer' -perm -111 | head -n1 || true)"
if [ -z "$CS_PATH" ]; then
  echo_red "[camera-streamer] could not locate camera-streamer binary in archive"
  ls -R "$TMP" || true
  exit 1
fi

install -Dm0755 "$CS_PATH" "$BIN"

# Version & --help health checks (no hardware required)
"$BIN" --version > /tmp/cs.version 2>&1 || true
if ! grep -qE 'camera-streamer|version|^v?[0-9]+\.' /tmp/cs.version; then
  echo_red "[camera-streamer] version check failed"
  cat /tmp/cs.version || true
  exit 1
fi

# --help may exit non-zero; only fail if it crashes or prints nothing
CS_STATUS=0
"$BIN" --help >/tmp/cs.help 2>&1 || CS_STATUS=$?
if [ ! -s /tmp/cs.help ] || grep -qiE 'segmentation fault|illegal instruction|bus error' /tmp/cs.help; then
  echo_red "[camera-streamer] --help produced no output or crashed"
  cat /tmp/cs.help || true
  exit 1
fi

echo_green "[camera-streamer] OK: $(head -n1 /tmp/cs.version || echo 'version unknown') (help exit=${CS_STATUS})"

# --- Libcamera/camera stack sanity (RPi only; safe in chroot, no hardware access) ---
if [ "${VARIANT}" = "raspi" ]; then
  echo_green "[libcamera] probing versions and libraries"
  (apt-cache policy libcamera0 2>/dev/null | sed -n '1,20p') || true
  dpkg -l | awk '/^ii/ && /libcamera|v4l2|raspberrypi/ {printf "[pkg] %-40s %s\n",$2,$3}' || true
  ldconfig -p 2>/dev/null | grep -E 'libcamera|v4l2' || true

  # Ensure KMS overlay for camera stack when using RPi kernel
  install -d /boot/firmware
  if ! grep -q '^dtoverlay=vc4-kms-v3d' /boot/firmware/config.txt 2>/dev/null; then
    echo "dtoverlay=vc4-kms-v3d" >> /boot/firmware/config.txt
    echo_green "[libcamera] added dtoverlay=vc4-kms-v3d to /boot/firmware/config.txt"
  fi
fi
