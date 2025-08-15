#!/usr/bin/env bash
set -euox pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap
export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

PIN_FILE="/files/etc/camera-streamer.version"
TAG_DEFAULT="0.2.8"

# ---- helpers -----------------------------------------------------------------
fetch() {
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 5 --retry-delay 2 --retry-all-errors -o "$out" "$url"
  else
    wget --tries=5 --waitretry=2 --retry-connrefused -O "$out" "$url"
  fi
}

read_pin() {
  local t=""
  if [ -f "$PIN_FILE" ]; then
    t="$(sed -e 's/^[vV]//' -e 's/[^0-9A-Za-z._-].*$//' "$PIN_FILE" | head -n1 || true)"
  elif [ -n "${CAMERA_STREAMER_TAG:-}" ]; then
    t="$(printf '%s' "$CAMERA_STREAMER_TAG" | sed 's/^[vV]//' || true)"
  fi
  # Accept X.Y or X.Y.Z (+ optional -/_suffix) or 'latest'
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

resolve_bin() {
  if command -v camera-streamer >/dev/null 2>&1; then
    command -v camera-streamer; return 0
  fi
  for p in /usr/bin/camera-streamer /usr/local/bin/camera-streamer /bin/camera-streamer; do
    [ -x "$p" ] && { echo "$p"; return 0; }
  done
  return 1
}

have_pkg() { apt-cache show "$1" >/dev/null 2>&1; }

# ---- environment -------------------------------------------------------------
apt-get update || true
apt-get install -y --no-install-recommends ca-certificates curl wget xz-utils tar || true

ARCH="$(dpkg --print-architecture)"                          # arm64 / armhf
CODENAME="$(. /etc/os-release; echo "${VERSION_CODENAME:-bookworm}")"
[ -n "$CODENAME" ] || CODENAME="bookworm"

# Prefer generic build on Debian; we’ll still try raspi if needed
PREFER_VARIANTS=(generic raspi)

# If we detect an RPi kernel, keep raspi as a later candidate (not first)
if [ -e /etc/default/raspberrypi-kernel ]; then
  :
fi

TAG="$(read_pin || true)"
if [ -z "${TAG:-}" ] || [ "$TAG" = "latest" ]; then
  rtag="$(gh_api_latest_tag || true)"
  TAG="${rtag:-$TAG_DEFAULT}"
fi

echo "[camera-streamer] will try install tag=v${TAG} arch=${ARCH} codename=${CODENAME}"

BASE="https://github.com/ayufan/camera-streamer/releases/download/v${TAG}"
TMP="$(mktemp -d)"

# candidates in priority order:
#  1) generic bookworm  2) generic bullseye
#  3) raspi   bookworm  4) raspi   bullseye
try_install_candidates() {
  local ok=0
  for VARIANT in "${PREFER_VARIANTS[@]}"; do
    for CODE in "${CODENAME}" bullseye; do
      local PKG="camera-streamer-${VARIANT}_${TAG}.${CODE}_${ARCH}.deb"
      # the project also publishes non-suffixed names sometimes:
      local ALT1="camera-streamer_${TAG}.${CODE}_${ARCH}.deb"
      local URL="${BASE}/${PKG}"
      local URL_ALT="${BASE}/${ALT1}"

      echo "[camera-streamer] trying: ${PKG}"
      local OUT="${TMP}/camera-streamer_${VARIANT}_${CODE}.deb"
      if fetch "$URL" "$OUT" || fetch "$URL_ALT" "$OUT"; then
        # Use apt so dependencies are resolved from configured repos
        if apt-get install -y --no-install-recommends "$OUT"; then
          echo "[camera-streamer] installed ${VARIANT} (${CODE})"
          ok=1; break
        else
          echo "[camera-streamer] apt install failed for ${VARIANT}/${CODE}, will try next candidate"
        fi
      else
        echo "[camera-streamer] not found: ${URL} (or ALT), trying next"
      fi
    done
    [ "$ok" -eq 1 ] && break
  done
  return "$ok"
}

# ---- install path ------------------------------------------------------------
if ! try_install_candidates; then
  # last resort: tarball (may be missing on some tags)
  case "$ARCH" in
    arm64|aarch64) ASSET_ARCH="linux_aarch64" ;;
    armhf|armel|arm) ASSET_ARCH="linux_armv7" ;;
    *) echo "[camera-streamer] unsupported arch: $ARCH"; exit 2 ;;
  esac
  local OUT="${TMP}/camera-streamer.tgz"
  local TARBALL="${BASE}/camera-streamer_${TAG}_${ASSET_ARCH}.tar.gz"
  echo "[camera-streamer] falling back to tarball: ${TARBALL}"
  if fetch "$TARBALL" "$OUT"; then
    tar -xzf "$OUT" -C "$TMP"
    CS_PATH="$(find "$TMP" -type f -name 'camera-streamer' -perm -111 | head -n1 || true)"
    [ -n "$CS_PATH" ] || { echo "[camera-streamer] binary not found in tarball"; ls -R "$TMP" || true; exit 1; }
    install -Dm0755 "$CS_PATH" /usr/local/bin/camera-streamer
  else
    echo "[camera-streamer] tarball not available for this tag (common), aborting"
    exit 1
  fi
fi

# Resolve final binary path
BIN="$(resolve_bin || true)"
if [ -z "${BIN:-}" ]; then
  echo "[camera-streamer] ERROR: camera-streamer not found after install"
  # If we installed raspi variant and the special libcamera isn’t present, hint:
  if ! have_pkg libcamera0 && ! have_pkg libcamera0.1; then
    echo "[camera-streamer] hint: camera deps missing; switching to generic variant is recommended."
  fi
  exit 1
fi
echo "[camera-streamer] using binary: $BIN"

# ---- health checks (no hardware required) ------------------------------------
set +e
"$BIN" --version > /tmp/cs.version 2>&1; CS_VERS_RC=$?
set -e
if [ $CS_VERS_RC -ne 0 ] || ! grep -qE 'camera-streamer|version|^v?[0-9]+\.' /tmp/cs.version; then
  echo "[camera-streamer] --version failed"; cat /tmp/cs.version || true
  exit 1
fi

CS_STATUS=0
"$BIN" --help >/tmp/cs.help 2>&1 || CS_STATUS=$?
if [ ! -s /tmp/cs.help ] || grep -qiE 'segmentation fault|illegal instruction|bus error' /tmp/cs.help; then
  echo "[camera-streamer] --help produced no output or crashed"
  cat /tmp/cs.help || true
  exit 1
fi

if command -v ldd >/dev/null 2>&1; then
  if MISSING="$(ldd "$BIN" 2>/dev/null | awk '/not found/ {print $1}')" && [ -n "$MISSING" ]; then
    echo "[camera-streamer] missing libs: $MISSING"; exit 1
  fi
fi

echo "[camera-streamer] OK: $(head -n1 /tmp/cs.version || echo 'version unknown') (help exit=${CS_STATUS})"

# ---- RPi libcamera overlay (RPi kernels) -------------------------------------
if [ -e /etc/default/raspberrypi-kernel ]; then
  install -d /boot/firmware
  if ! grep -q '^dtoverlay=vc4-kms-v3d' /boot/firmware/config.txt 2>/dev/null; then
    echo "dtoverlay=vc4-kms-v3d" >> /boot/firmware/config.txt
    echo "[libcamera] added dtoverlay=vc4-kms-v3d to /boot/firmware/config.txt"
  fi
fi
