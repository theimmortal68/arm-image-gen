#!/usr/bin/env bash
set -Eeuxo pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap

export DEBIAN_FRONTEND=noninteractive

# ---- config / pins ------------------------------------------------------------
PIN_FILE="/files/etc/camera-streamer.version"
TAG_DEFAULT="0.2.8"

read_pin() {
  local t=""
  if [ -f "$PIN_FILE" ]; then
    t="$(sed -e 's/^[vV]//' -e 's/[^0-9A-Za-z._-].*$//' "$PIN_FILE" | head -n1)"
  elif [ -n "${CAMERA_STREAMER_TAG:-}" ]; then
    t="$(printf '%s' "$CAMERA_STREAMER_TAG" | sed 's/^[vV]//')"
  fi
  printf '%s' "${t:-}"
}

TAG="$(read_pin || true)"
[ -n "$TAG" ] || TAG="$TAG_DEFAULT"

# ---- arch / variant detection -------------------------------------------------
ARCH="$(dpkg --print-architecture)"
VARIANT="generic"
[ -e /etc/default/raspberrypi-kernel ] && VARIANT="raspi"

case "$ARCH" in
  arm64|aarch64) ASSET_ARCH="linux_aarch64" ;;
  armhf|armel|arm) ASSET_ARCH="linux_armv7" ;; # best-effort 32-bit
  *) echo_red "[camera-streamer] unsupported arch: $ARCH"; exit 2 ;;
esac

BIN="/usr/local/bin/camera-streamer"
TMP="/tmp/camera-streamer.$$"
mkdir -p "$TMP"

# ---- if a binary was staged via scripts/files, prefer that --------------------
if [ -x /files/usr/local/bin/camera-streamer ]; then
  install -Dm0755 /files/usr/local/bin/camera-streamer "$BIN"
  echo_green "[camera-streamer] installed staged binary from /files"
else
  # If no explicit pin but an existing binary is present, keep it (just health-check)
  if [ -x "$BIN" ] && [ ! -f "$PIN_FILE" ] && [ -z "${CAMERA_STREAMER_TAG:-}" ]; then
    echo_green "[camera-streamer] existing binary found; no pin requested, keeping it"
  else
    # Download the requested/pinned version (fall back to default if API unavailable)
    ASSET="camera-streamer_${TAG}_${ASSET_ARCH}.tar.gz"
    URL="https://github.com/ayufan/camera-streamer/releases/download/v${TAG}/${ASSET}"
    echo_green "[camera-streamer] fetching ${URL}"

    apt-get update
    apt-get install -y --no-install-recommends ca-certificates curl xz-utils tar jq || true

    # Try API for latest if TAG looks like 'latest'
    if [ "$TAG" = "latest" ]; then
      if curl -fsSL "https://api.github.com/repos/ayufan/camera-streamer/releases/latest" >/tmp/cs.latest.json 2>/dev/null; then
        TAG="$(jq -r '.tag_name' /tmp/cs.latest.json | sed 's/^v//')"
        ASSET="camera-streamer_${TAG}_${ASSET_ARCH}.tar.gz"
        URL="https://github.com/ayufan/camera-streamer/releases/download/v${TAG}/${ASSET}"
      fi
    fi

    curl -fL --retry 5 --retry-delay 2 --retry-all-errors -o "${TMP}/cs.tgz" "$URL"
    tar -xzf "${TMP}/cs.tgz" -C "$TMP"

    CS_PATH="$(find "$TMP" -type f -name 'camera-streamer' -perm -111 | head -n1 || true)"
    if [ -z "$CS_PATH" ]; then
      echo_red "[camera-streamer] could not locate binary in archive"; ls -R "$TMP" || true; exit 1
    fi
    install -Dm0755 "$CS_PATH" "$BIN"
  fi
fi

# ---- health checks (no hardware required) ------------------------------------
set +e
"$BIN" --version > /tmp/cs.version 2>&1
CS_VERS_RC=$?
set -e
if [ $CS_VERS_RC -ne 0 ] || ! grep -qE 'camera-streamer|version|^v?[0-9]+\.' /tmp/cs.version; then
  echo_red "[camera-streamer] version check failed"
  cat /tmp/cs.version || true
  exit 1
fi

CS_STATUS=0
"$BIN" --help >/tmp/cs.help 2>&1 || CS_STATUS=$?
if [ ! -s /tmp/cs.help ] || grep -qiE 'segmentation fault|illegal instruction|bus error' /tmp/cs.help; then
  echo_red "[camera-streamer] --help produced no output or crashed"
  cat /tmp/cs.help || true
  exit 1
fi

echo_green "[camera-streamer] OK: $(head -n1 /tmp/cs.version || echo 'version unknown') (help exit=${CS_STATUS})"

# ---- Libcamera/camera stack sanity (RPi only) --------------------------------
if [ "$VARIANT" = "raspi" ]; then
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

# note: we do NOT install a camera-streamer systemd unit.
# Crowsnest will orchestrate the streaming process.
