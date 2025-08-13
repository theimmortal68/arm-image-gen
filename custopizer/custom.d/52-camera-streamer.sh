#!/bin/bash
# Install camera-streamer from the latest release (tolerant health check).
set -x
set -e
export LC_ALL=C
source /common.sh; install_cleanup_trap

# retry polyfill: usage → retry <attempts> <delay> <cmd...>
type retry >/dev/null 2>&1 || retry() {
  local tries="$1"; local delay="$2"; shift 2
  local n=0
  until "$@"; do
    n=$((n+1))
    [ "$n" -ge "$tries" ] && return 1
    sleep "$delay"
  done
}

export DEBIAN_FRONTEND=noninteractive
retry 4 2 apt-get update
apt-get install -y --no-install-recommends ca-certificates wget curl

CODENAME="$(. /etc/os-release; echo "${VERSION_CODENAME:-bookworm}")"
ARCH="$(dpkg --print-architecture)"
VARIANT="generic"
# If Raspberry Pi kernel package is present, use raspi variant
[ -e /etc/default/raspberrypi-kernel ] && VARIANT="raspi"

# Pick latest tag (best-effort), fallback to a known good
TAG="$(curl -fsSL https://api.github.com/repos/ayufan/camera-streamer/releases/latest | sed -nE 's/.*"tag_name": *"v?([^"]+)".*/\1/p' | head -n1)" || true
[ -n "$TAG" ] || TAG="0.2.8"

PKG="camera-streamer-${VARIANT}_${TAG}.${CODENAME}_${ARCH}.deb"
URL="https://github.com/ayufan/camera-streamer/releases/download/v${TAG}/${PKG}"
TMP="/tmp/${PKG}"

echo_green "[camera-streamer] installing variant=${VARIANT} tag=v${TAG} arch=${ARCH} codename=${CODENAME}"

# Try codename match first, then bullseye as a fallback
if ! wget -O "$TMP" "$URL"; then
  ALT="camera-streamer-${VARIANT}_${TAG}.bullseye_${ARCH}.deb"
  ALT_URL="https://github.com/ayufan/camera-streamer/releases/download/v${TAG}/${ALT}"
  echo_red "[camera-streamer] ${PKG} not found, trying: ${ALT}"
  wget -O "$TMP" "$ALT_URL"
fi

apt-get install -y "$TMP"

# -------- Health checks (tolerant) --------
BIN="$(command -v camera-streamer || true)"
if [ -z "$BIN" ]; then
  echo_red "[camera-streamer] ERROR: binary not found in PATH"
  exit 1
fi

# Ensure dependencies are resolvable
if MISSING="$(ldd "$BIN" | awk '/not found/ {print $1}')" && [ -n "$MISSING" ]; then
  echo_red "[camera-streamer] ERROR: missing libs: $MISSING"
  exit 1
fi

# Version must succeed
if ! "$BIN" --version >/tmp/cs.version 2>&1; then
  echo_red "[camera-streamer] ERROR: --version failed"
  cat /tmp/cs.version || true
  exit 1
fi

# Help is best-effort: accept non-zero exit if output looks sane
CS_STATUS=0
"$BIN" --help >/tmp/cs.help 2>&1 || CS_STATUS=$?
if [ ! -s /tmp/cs.help ] || grep -qiE 'segmentation fault|illegal instruction|bus error' /tmp/cs.help; then
  echo_red "[camera-streamer] ERROR: --help produced no output or crashed"
  cat /tmp/cs.help || true
  exit 1
fi
# If we got here, help output is present; it’s fine even if exit code != 0
echo_green "[camera-streamer] OK: $(head -n1 /tmp/cs.version || echo 'version unknown') (help exit=${CS_STATUS})"
