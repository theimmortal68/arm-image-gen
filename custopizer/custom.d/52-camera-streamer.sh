#!/usr/bin/env bash
set -euox pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap
export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

PIN_FILE="/files/etc/camera-streamer.version"
TAG_DEFAULT="0.2.8"

# --- helpers -------------------------------------------------------------------
read_pin() {
  local t=""
  if [ -f "$PIN_FILE" ]; then
    t="$(sed -e 's/^[vV]//' -e 's/[^0-9A-Za-z._-].*$//' "$PIN_FILE" | head -n1 || true)"
  elif [ -n "${CAMERA_STREAMER_TAG:-}" ]; then
    t="$(printf '%s' "$CAMERA_STREAMER_TAG" | sed 's/^[vV]//' || true)"
  fi
  # Accept X.Y or X.Y.Z optionally with -/_suffix, or 'latest'; otherwise blank
  if [ -n "${t:-}" ] && ! printf '%s' "$t" | grep -Eq '^[0-9]+(\.[0-9]+){1,2}([._-][0-9A-Za-z]+)?$|^latest$'; then
    t=""
  fi
  printf '%s' "${t:-}"
}

gh_api_latest_tag() {
  local api="https://api.github.com/repos/ayufan/camera-streamer/releases/latest" tag=""
  if command -v jq >/dev/null 2>&1; then
    tag="$(curl -fsSL "$api" | jq -r '.tag_name' | sed 's/^v//' || true)"
  else
    tag="$(curl -fsSL "$api" | sed -n 's/.*"tag_name":[[:space:]]*"\(v\{0,1\}[^"]*\)".*/\1/p' | head -n1 | sed 's/^v//' || true)"
  fi
  printf '%s' "$tag"
}

first_ok_url() {
  for u in "$@"; do
    if curl -fsSLI --retry 3 --retry-delay 2 "$u" >/dev/null 2>&1; then
      echo "$u"; return 0
    fi
  done
  return 1
}

resolve_bin() {
  if command -v camera-streamer >/dev/null 2>&1; then
    command -v camera-streamer
    return 0
  fi
  for p in /usr/local/bin/camera-streamer /usr/bin/camera-streamer /bin/camera-streamer; do
    [ -x "$p" ] && { echo "$p"; return 0; }
  done
  return 1
}

# --- resolve version/tag -------------------------------------------------------
TAG="$(read_pin || true)"
if [ -z "${TAG:-}" ] || [ "$TAG" = "latest" ]; then
  rtag="$(gh_api_latest_tag || true)"
  TAG="${rtag:-$TAG_DEFAULT}"
fi

# --- arch / variant / codename -------------------------------------------------
ARCH="$(dpkg --print-architecture)"                    # e.g., arm64, armhf
CODENAME="$(. /etc/os-release; echo "${VERSION_CODENAME:-bookworm}")"
[ -n "$CODENAME" ] || CODENAME="bookworm"

VARIANT="generic"
if [ -e /etc/default/raspberrypi-kernel ] || grep -qi 'raspberry pi' /proc/device-tree/model 2>/dev/null; then
  VARIANT="raspi"
fi

case "$ARCH" in
  arm64|aarch64) ASSET_ARCH="linux_aarch64" ;;
  armhf|armel|arm) ASSET_ARCH="linux_armv7" ;;
  *) echo "[camera-streamer] unsupported dpkg arch: $ARCH"; exit 2 ;;
esac

# --- deps ----------------------------------------------------------------------
apt-get update || true
apt-get install -y --no-install-recommends ca-certificates curl wget xz-utils tar dpkg || true

# --- prefer .deb assets, then fallback to tarball ------------------------------
BASE="https://github.com/ayufan/camera-streamer/releases/download/v${TAG}"
DEB_CANDIDATES=(
  "${BASE}/camera-streamer-${VARIANT}_${TAG}.${CODENAME}_${ARCH}.deb"
  "${BASE}/camera-streamer-${VARIANT}_${TAG}.bullseye_${ARCH}.deb"
  "${BASE}/camera-streamer_${TAG}.${CODENAME}_${ARCH}.deb"
  "${BASE}/camera-streamer_${TAG}.bullseye_${ARCH}.deb"
)
TARBALL="${BASE}/camera-streamer_${TAG}_${ASSET_ARCH}.tar.gz"

CHOSEN_URL="$(first_ok_url "${DEB_CANDIDATES[@]}")" || CHOSEN_URL="$TARBALL"

echo "[camera-streamer] resolved TAG: ${TAG}"
echo "[camera-streamer] chosen URL: ${CHOSEN_URL}"

TMP="$(mktemp -d)"

# If a staged binary exists under /files, prefer that and skip downloads
if [ -x /files/usr/local/bin/camera-streamer ]; then
  install -Dm0755 /files/usr/local/bin/camera-streamer /usr/local/bin/camera-streamer
  echo "[camera-streamer] installed staged binary from /files"
else
  if printf '%s' "$CHOSEN_URL" | grep -q '\.deb$'; then
    # --- .deb path
    OUT="${TMP}/camera-streamer.deb"
    curl -fL --retry 5 --retry-delay 2 --retry-all-errors -o "$OUT" "$CHOSEN_URL"
    dpkg -i "$OUT" || apt-get -y -f install
  else
    # --- tarball fallback
    OUT="${TMP}/camera-streamer.tgz"
    curl -fL --retry 5 --retry-delay 2 --retry-all-errors -o "$OUT" "$CHOSEN_URL"
    tar -xzf "$OUT" -C "$TMP"
    CS_PATH="$(find "$TMP" -type f -name 'camera-streamer' -perm -111 | head -n1 || true)"
    [ -n "$CS_PATH" ] || { echo "[camera-streamer] binary not found in tarball"; ls -R "$TMP" || true; exit 1; }
    install -Dm0755 "$CS_PATH" /usr/local/bin/camera-streamer
  fi
fi

# --- resolve final binary path -------------------------------------------------
BIN="$(resolve_bin || true)"
if [ -z "${BIN:-}" ]; then
  echo "[camera-streamer] ERROR: camera-streamer not found in PATH after install"
  exit 1
fi
echo "[camera-streamer] using binary: $BIN"

# --- health checks (no hardware required) -------------------------------------
set +e
"$BIN" --version > /tmp/cs.version 2>&1; CS_VERS_RC=$?
set -e
if [ $CS_VERS_RC -ne 0 ] || ! grep -qE 'camera-streamer|version|^v?[0-9]+\.' /tmp/cs.version; then
  echo "[camera-streamer] version check failed"; cat /tmp/cs.version || true; exit 1
fi
"$BIN" --help >/tmp/cs.help 2>&1 || true
if [ ! -s /tmp/cs.help ] || grep -qiE 'segmentation fault|illegal instruction|bus error' /tmp/cs.help; then
  echo "[camera-streamer] --help produced no output or crashed"; cat /tmp/cs.help || true; exit 1
fi

if command -v ldd >/dev/null 2>&1; then
  ldd "$BIN" | awk '/=>/ {print "[ldd] " $0}' || true
fi

echo "[camera-streamer] OK: $(head -n1 /tmp/cs.version || echo 'version unknown')"

# --- Libcamera/camera stack sanity (RPi only) ---------------------------------
if [ "$VARIANT" = "raspi" ]; then
  echo "[libcamera] probing versions and libraries"
  (apt-cache policy libcamera0 2>/dev/null | sed -n '1,20p') || true
  dpkg -l | awk '/^ii/ && /(libcamera|v4l2|raspberrypi)/ {printf "[pkg] %-40s %s\n",$2,$3}' || true
  ldconfig -p 2>/dev/null | grep -E 'libcamera|v4l2' || true

  install -d /boot/firmware
  if ! grep -q '^dtoverlay=vc4-kms-v3d' /boot/firmware/config.txt 2>/dev/null; then
    echo "dtoverlay=vc4-kms-v3d" >> /boot/firmware/config.txt
    echo "[libcamera] added dtoverlay=vc4-kms-v3d to /boot/firmware/config.txt"
  fi
fi

# No unit here; crowsnest will orchestrate streaming.
