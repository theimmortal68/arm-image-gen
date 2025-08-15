#!/usr/bin/env bash
set -Eeuxo pipefail
export LC_ALL=C
# shellcheck disable=SC1091
source /common.sh; install_cleanup_trap
export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# ---------------- helpers ----------------
fetch() { # url out
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 5 --retry-delay 2 --retry-all-errors -o "$out" "$url"
  else
    wget --tries=5 --waitretry=2 --retry-connrefused -O "$out" "$url"
  fi
}
head_ok() { # url
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSLI --retry 3 --retry-delay 2 "$url" >/dev/null 2>&1
  else
    wget -q --spider "$url"
  fi
}
resolve_bin() {
  command -v camera-streamer >/dev/null 2>&1 && { command -v camera-streamer; return 0; }
  for p in /usr/bin/camera-streamer /usr/local/bin/camera-streamer; do
    [ -x "$p" ] && { echo "$p"; return 0; }
  done
  return 1
}
purge_cs_pkgs() {
  apt-get remove -y --purge camera-streamer-raspi camera-streamer-generic camera-streamer || true
}

# ---------------- env/detect --------------
apt-get update || true
apt-get install -y --no-install-recommends ca-certificates curl wget xz-utils tar jq || true

ARCH="$(dpkg --print-architecture)"                       # arm64/armhf
CODENAME="$(. /etc/os-release; echo "${VERSION_CODENAME:-bookworm}")"

# Detect a “true Pi” userspace (kernel pkg marker) and/or Raspberry Pi libcamera
IS_RPI=0
[ -e /etc/default/raspberrypi-kernel ] && IS_RPI=1
grep -qi 'raspberry pi' /proc/device-tree/model 2>/dev/null && IS_RPI=1 || true
HAS_PI_LIBCAM=0
apt-cache policy libcamera0.1 2>/dev/null | grep -qi 'archive\.raspberrypi\.com' && HAS_PI_LIBCAM=1 || true
dpkg -l | awk '$2 ~ /^libcamera0\.1$/ && $1=="ii"{print}' | grep -q . && HAS_PI_LIBCAM=$HAS_PI_LIBCAM || true

# Variant preference (overridable)
VARIANT="${CAMERA_STREAMER_VARIANT:-auto}"
if [ "$VARIANT" = "auto" ]; then
  if [ "$IS_RPI" -eq 1 ] && [ "$HAS_PI_LIBCAM" -eq 1 ]; then
    VARIANT="raspi"
  else
    VARIANT="generic"
  fi
fi

case "$ARCH" in
  arm64|aarch64) ASSET_ARCH="arm64" ;;
  armhf|arm)     ASSET_ARCH="armhf" ;;
  *) echo_red "[camera-streamer] unsupported arch: $ARCH"; exit 2 ;;
esac

# Pick a tag; allow pin via /files/etc/camera-streamer.version or env CAMERA_STREAMER_TAG
PIN_FILE="/files/etc/camera-streamer.version"
TAG=""
[ -f "$PIN_FILE" ] && TAG="$(sed -e 's/^[vV]//' -e 's/[^0-9A-Za-z._-].*$//' "$PIN_FILE" | head -n1 || true)"
[ -n "${CAMERA_STREAMER_TAG:-}" ] && TAG="$(printf '%s' "$CAMERA_STREAMER_TAG" | sed 's/^[vV]//')"
if [ -z "$TAG" ] || [ "$TAG" = "latest" ]; then
  TAG="$(curl -fsSL "https://api.github.com/repos/ayufan/camera-streamer/releases/latest" \
        | jq -r '.tag_name' | sed 's/^v//' || true)"
fi
[ -n "$TAG" ] || TAG="0.2.8"

echo_green "[camera-streamer] target variant=${VARIANT} tag=v${TAG} arch=${ARCH} codename=${CODENAME}"

BASE="https://github.com/ayufan/camera-streamer/releases/download/v${TAG}"

install_variant() { # raspi|generic
  local variant="$1" tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  local pkg="camera-streamer-${variant}_${TAG}.${CODENAME}_${ARCH}.deb"
  local url="${BASE}/${pkg}"
  local out="${tmp}/${pkg}"
  if ! head_ok "$url"; then
    # fall back to bullseye asset naming or unified package name
    pkg="camera-streamer-${variant}_${TAG}.bullseye_${ARCH}.deb"
    url="${BASE}/${pkg}"
    if ! head_ok "$url"; then
      pkg="camera-streamer_${TAG}.${CODENAME}_${ARCH}.deb"
      url="${BASE}/${pkg}"
      head_ok "$url" || { echo_red "[camera-streamer] no .deb asset for ${variant}"; return 1; }
    fi
  fi
  echo_green "[camera-streamer] downloading ${pkg}"
  fetch "$url" "$out"
  apt-get install -y "$out"
}

# --------------- Install flow -----------------
# First attempt: chosen VARIANT
purge_cs_pkgs || true
if ! install_variant "$VARIANT"; then
  echo_red "[camera-streamer] install failed for ${VARIANT}"
  exit 1
fi

BIN="$(resolve_bin || true)"
[ -n "${BIN:-}" ] || { echo_red "[camera-streamer] binary missing after install"; exit 1; }
echo_green "[camera-streamer] using binary: $BIN"

set +e
"$BIN" --version > /tmp/cs.version 2>&1
VERS_RC=$?
set -e

if [ $VERS_RC -ne 0 ]; then
  # Common case: raspi build on non-Pi libcamera → libpisp symbol failure
  if grep -q 'libcamera\.so.*undefined symbol.*libpisp' /tmp/cs.version 2>/dev/null; then
    echo_red "[camera-streamer] libpisp symbol missing in libcamera; switching to generic build"
    purge_cs_pkgs || true
    if install_variant "generic"; then
      BIN="$(resolve_bin || true)"
      [ -n "$BIN" ] || { echo_red "[camera-streamer] binary missing after generic install"; exit 1; }
      "$BIN" --version > /tmp/cs.version 2>&1 || { cat /tmp/cs.version || true; exit 1; }
    else
      echo_red "[camera-streamer] generic install failed after raspi removal"
      exit 1
    fi
  else
    echo_red "[camera-streamer] --version failed"; cat /tmp/cs.version || true; exit 1
  fi
fi

# --help may exit non-zero; only fail on crash or no output
CS_STATUS=0
"$BIN" --help >/tmp/cs.help 2>&1 || CS_STATUS=$?
if [ ! -s /tmp/cs.help ] || grep -qiE 'segmentation fault|illegal instruction|bus error' /tmp/cs.help; then
  echo_red "[camera-streamer] --help produced no output or crashed"
  cat /tmp/cs.help || true
  exit 1
fi

# Missing shared libs?
if command -v ldd >/dev/null 2>&1; then
  if MISSING="$(ldd "$BIN" 2>/dev/null | awk '/not found/ {print $1}')" && [ -n "$MISSING" ]; then
    echo_red "[camera-streamer] missing libs: $MISSING"
    exit 1
  fi
fi

echo_green "[camera-streamer] OK: $(head -n1 /tmp/cs.version || echo 'version unknown') (help exit=${CS_STATUS})"
