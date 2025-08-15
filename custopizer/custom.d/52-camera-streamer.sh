#!/usr/bin/env bash
set -euox pipefail
export LC_ALL=C
# shellcheck disable=SC1091
source /common.sh; install_cleanup_trap
export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

PIN_FILE="/files/etc/camera-streamer.version"
TAG_DEFAULT="0.2.8"

# ---------- helpers ------------------------------------------------------------
fetch() {
  # fetch URL to file with retries (curl preferred, wget fallback)
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 5 --retry-delay 2 --retry-all-errors -o "$out" "$url"
  else
    wget --tries=5 --waitretry=2 --retry-connrefused -O "$out" "$url"
  fi
}

head_ok() {
  # return 0 if HEAD works
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSLI --retry 3 --retry-delay 2 "$url" >/dev/null 2>&1
  else
    wget --spider -q "$url"
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

resolve_bin() {
  if command -v camera-streamer >/dev/null 2>&1; then
    command -v camera-streamer; return 0
  fi
  for p in /usr/bin/camera-streamer /usr/local/bin/camera-streamer /bin/camera-streamer; do
    [ -x "$p" ] && { echo "$p"; return 0; }
  done
  return 1
}

# ---------- environment / detection -------------------------------------------
apt-get update || true
apt-get install -y --no-install-recommends ca-certificates curl wget xz-utils tar dpkg jq || true

ARCH="$(dpkg --print-architecture)"                       # arm64 / armhf
CODENAME="$(. /etc/os-release; echo "${VERSION_CODENAME:-bookworm}")"
[ -n "$CODENAME" ] || CODENAME="bookworm"

IS_RPI=0
[ -e /etc/default/raspberrypi-kernel ] && IS_RPI=1
grep -qi 'raspberry pi' /proc/device-tree/model 2>/dev/null && IS_RPI=1 || true

HAS_RPI_LIBCAM=0
apt-cache policy libcamera0.1 2>/dev/null | grep -q Candidate && HAS_RPI_LIBCAM=1 || true
dpkg -l | grep -qE '^ii\s+libcamera0\.1' && HAS_RPI_LIBCAM=1 || true

# Prefer raspi on true Raspberry Pi images (to match libcamera stack); else generic first
if [ "$IS_RPI" -eq 1 ] || [ "$HAS_RPI_LIBCAM" -eq 1 ]; then
  PREFER_VARIANTS=(raspi generic)
else
  PREFER_VARIANTS=(generic raspi)
fi

case "$ARCH" in
  arm64|aarch64) ASSET_ARCH="linux_aarch64" ;;
  armhf|armel|arm) ASSET_ARCH="linux_armv7" ;;
  *) echo "[camera-streamer] unsupported dpkg arch: $ARCH"; exit 2 ;;
esac

# ---------- pick a tag ---------------------------------------------------------
TAG="$(read_pin || true)"
if [ -z "${TAG:-}" ] || [ "$TAG" = "latest" ]; then
  # Try latest; if no viable asset found, iterate a few past releases
  # Use GitHub API with jq for tags
  echo "[camera-streamer] resolving latest working tag for ${ARCH} (${CODENAME})"
  tags=()
  mapfile -t tags < <(curl -fsSL "https://api.github.com/repos/ayufan/camera-streamer/releases?per_page=10" \
    | jq -r '.[].tag_name' 2>/dev/null | sed 's/^v//' )
  tags=( "${tags[@]}" "$TAG_DEFAULT" )

  for t in "${tags[@]}"; do
    [ -n "$t" ] || continue
    BASE="https://github.com/ayufan/camera-streamer/releases/download/v${t}"
    found=0
    for VARIANT in "${PREFER_VARIANTS[@]}"; do
      for CODE in "${CODENAME}" bullseye; do
        URL_DEB_1="${BASE}/camera-streamer-${VARIANT}_${t}.${CODE}_${ARCH}.deb"
        URL_DEB_2="${BASE}/camera-streamer_${t}.${CODE}_${ARCH}.deb"
        if head_ok "$URL_DEB_1" || head_ok "$URL_DEB_2"; then
          TAG="$t"
          found=1
          break 2
        fi
      done
    done
    if [ "$found" -eq 1 ]; then break; fi
  done

  [ -n "${TAG:-}" ] || TAG="$TAG_DEFAULT"
fi

echo "[camera-streamer] chosen TAG: v${TAG} (arch=${ARCH} codename=${CODENAME}; prefer ${PREFER_VARIANTS[*]})"

# ---------- install (prefer .deb; fallback tarball) ----------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# staged binary override
if [ -x /files/usr/local/bin/camera-streamer ]; then
  install -Dm0755 /files/usr/local/bin/camera-streamer /usr/local/bin/camera-streamer
  echo "[camera-streamer] installed staged binary from /files"
else
  BASE="https://github.com/ayufan/camera-streamer/releases/download/v${TAG}"
  installed=1  # assume failure; set to 0 on success

  # Try preferred variants / codenames in order
  for VARIANT in "${PREFER_VARIANTS[@]}"; do
    for CODE in "${CODENAME}" bullseye; do
      PKG="camera-streamer-${VARIANT}_${TAG}.${CODE}_${ARCH}.deb"
      ALT="camera-streamer_${TAG}.${CODE}_${ARCH}.deb"
      URL="${BASE}/${PKG}"
      URL_ALT="${BASE}/${ALT}"
      OUT="${TMP}/camera-streamer_${VARIANT}_${CODE}.deb"

      if head_ok "$URL" || head_ok "$URL_ALT"; then
        echo "[camera-streamer] downloading: ${URL} (or ALT)"
        fetch "${URL}" "$OUT" || fetch "${URL_ALT}" "$OUT" || true
        if [ -s "$OUT" ]; then
          echo "[camera-streamer] apt-install ${VARIANT} (${CODE})"
          if apt-get install -y --no-install-recommends "$OUT"; then
            installed=0
            break 2
          else
            echo "[camera-streamer] apt install failed for ${VARIANT}/${CODE}; trying next candidate"
          fi
        fi
      else
        echo "[camera-streamer] asset not found for ${VARIANT}/${CODE}"
      fi
    done
  done

  if [ "$installed" -ne 0 ]; then
    # final fallback: tarball
    TARBALL="${BASE}/camera-streamer_${TAG}_${ASSET_ARCH}.tar.gz"
    echo "[camera-streamer] falling back to tarball: ${TARBALL}"
    OUTTGZ="${TMP}/camera-streamer.tgz"
    if fetch "$TARBALL" "$OUTTGZ"; then
      tar -xzf "$OUTTGZ" -C "$TMP"
      CS_PATH="$(find "$TMP" -type f -name 'camera-streamer' -perm -111 | head -n1 || true)"
      [ -n "$CS_PATH" ] || { echo "[camera-streamer] binary not found in tarball"; ls -R "$TMP" || true; exit 1; }
      install -Dm0755 "$CS_PATH" /usr/local/bin/camera-streamer
    else
      echo "[camera-streamer] no usable asset found for v${TAG} (${ARCH}); aborting"
      exit 1
    fi
  fi
fi

# ---------- resolve binary & health checks -------------------------------------
BIN="$(resolve_bin || true)"
if [ -z "${BIN:-}" ]; then
  echo "[camera-streamer] ERROR: camera-streamer not found after install"
  exit 1
fi
echo "[camera-streamer] using binary: $BIN"

set +e
"$BIN" --version > /tmp/cs.version 2>&1; CS_VERS_RC=$?
set -e
if [ $CS_VERS_RC -ne 0 ] || ! grep -qE 'camera-streamer|version|^v?[0-9]+\.' /tmp/cs.version; then
  echo "[camera-streamer] --version failed"; cat /tmp/cs.version || true
  # If we preferred raspi and failed here, try generic before giving up
  if echo "${PREFER_VARIANTS[*]}" | grep -q '^raspi'; then
    echo "[camera-streamer] retrying with generic variant due to version failure"
    PREFER_VARIANTS=(generic)
    # Re-run install loop once for generic
    installed=1
    BASE="https://github.com/ayufan/camera-streamer/releases/download/v${TAG}"
    for CODE in "${CODENAME}" bullseye; do
      PKG="camera-streamer-generic_${TAG}.${CODE}_${ARCH}.deb"
      ALT="camera-streamer_${TAG}.${CODE}_${ARCH}.deb"
      URL="${BASE}/${PKG}"
      URL_ALT="${BASE}/${ALT}"
      OUT="${TMP}/camera-streamer_generic_${CODE}.deb"
      if head_ok "$URL" || head_ok "$URL_ALT"; then
        fetch "${URL}" "$OUT" || fetch "${URL_ALT}" "$OUT" || true
        if [ -s "$OUT" ] && apt-get install -y --no-install-recommends "$OUT"; then
          installed=0; break
        fi
      fi
    done
    if [ "$installed" -eq 0 ]; then
      BIN="$(resolve_bin || true)"
      [ -n "$BIN" ] || { echo "[camera-streamer] still missing after generic retry"; exit 1; }
      "$BIN" --version > /tmp/cs.version 2>&1 || { cat /tmp/cs.version || true; exit 1; }
    else
      echo "[camera-streamer] generic retry failed"; exit 1
    fi
  else
    exit 1
  fi
fi

"$BIN" --help >/tmp/cs.help 2>&1 || true
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

echo "[camera-streamer] OK: $(head -n1 /tmp/cs.version || echo 'version unknown')"

# ---------- Raspberry Pi overlay for libcamera --------------------------------
if [ "$IS_RPI" -eq 1 ]; then
  install -d /boot/firmware
  grep -q '^dtoverlay=vc4-kms-v3d' /boot/firmware/config.txt 2>/dev/null || {
    echo "dtoverlay=vc4-kms-v3d" >> /boot/firmware/config.txt
    echo "[libcamera] added dtoverlay=vc4-kms-v3d to /boot/firmware/config.txt"
  }
fi

# No unit here; Crowsnest orchestrates streaming.
