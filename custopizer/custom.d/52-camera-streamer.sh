#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

# Aligns with Crowsnest: installs camera backends only (no services).
# RPi: libcamera + rpicam-apps + camera-streamer
# Orange Pi 5 series: ustreamer (V4L2 MJPEG)
# Crowsnest config chooses the backend via [cam] section:
#   mode: camera-streamer  (RPi)
#   mode: ustreamer        (OPi/USB cams)
#
# Docs:
# - Crowsnest [cam] modes & backends: https://crowsnest.mainsail.xyz/configuration/cam-section
# - Crowsnest backends overview:      https://crowsnest.mainsail.xyz/faq/backends-from-crowsnest
# - RPi camera stack (Bookworm):      https://www.raspberrypi.com/documentation/computers/camera_software.html
# - camera-streamer project:          https://github.com/ayufan/camera-streamer

source /common.sh; install_cleanup_trap

# -------- Helpers --------
is_file()  { [ -f "$1" ]; }
is_dir()   { [ -d "$1" ]; }
in_file()  { grep -qE "$2" "$1"; }
arch()     { dpkg --print-architecture; }

model_from_dt() {
  local m="/proc/device-tree/model"
  if [ -r "$m" ]; then tr -d '\0' < "$m"; else echo ""; fi
}

is_rpi() {
  local m; m="$(model_from_dt || true)"
  printf '%s' "$m" | grep -iq 'raspberry pi'
}

is_rpi5() {
  local m; m="$(model_from_dt || true)"
  printf '%s' "$m" | grep -iq 'raspberry pi 5'
}

is_orangepi5() {
  # Matches Orange Pi 5 / 5 Plus / 5 Max (rk3588 family)
  local m; m="$(model_from_dt || true)"
  if printf '%s' "$m" | grep -iq 'orange pi 5'; then return 0; fi
  if is_file /etc/armbian-release && grep -qi 'orangepi' /etc/armbian-release; then
    # Heuristic: RK3588 boards
    grep -qiE '5(\+| plus| max)?' /etc/armbian-release || true
  fi
}

apt_update_once() {
  # Some images pin Raspberry Pi repo in base; just update safely.
  APT_LISTCHANGES_FRONTEND=none apt-get update
}

apt_install_norec() {
  # shellcheck disable=SC2068
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $@
}

# -------- RPi camera stack (Bookworm) --------
install_rpi_libcamera_stack() {
  apt_update_once
  # Prefer Raspberry Pi repo names (Bookworm): rpicam-apps + libcamera0 + tools.
  # Fall back to Debian names if needed.
  apt_install_norec \
    v4l-utils \
    libcamera0 \
    libcamera-tools || true

  if ! dpkg -s rpicam-apps >/dev/null 2>&1; then
    apt_install_norec rpicam-apps || apt_install_norec libcamera-apps || true
  fi

  # Basic sanity (don’t fail the build if tools are missing)
  if command -v rpicam-hello >/dev/null 2>&1; then rpicam-hello --version || true; fi
  if command -v libcamera-hello >/dev/null 2>&1; then libcamera-hello --version || true; fi
}

# -------- camera-streamer for RPi (preferred) --------
build_or_install_camera_streamer() {
  # Try prebuilt deb first (recommended upstream). If that fails, build from source.
  # We keep this robust without hardcoding exact asset names.
  apt_update_once
  apt_install_norec ca-certificates curl git xz-utils

  tmpd="$(mktemp -d)"; trap 'rm -rf "$tmpd"' EXIT

  # Try to discover a suitable .deb from the latest release (arm64 Bookworm).
  # If discovery fails (asset names change), we fall back to building.
  set +e
  CS_DEB_URL="$(curl -fsSL https://api.github.com/repos/ayufan/camera-streamer/releases/latest \
    | grep -Eo '"browser_download_url":\s*"[^"]+\.deb"' \
    | grep -E 'arm64|aarch64' \
    | head -n1 \
    | cut -d'"' -f4)"
  set -e

  if [ -n "${CS_DEB_URL:-}" ]; then
    echo "Found prebuilt camera-streamer: $CS_DEB_URL"
    curl -fL "$CS_DEB_URL" -o "$tmpd/camera-streamer.deb"
    dpkg -i "$tmpd/camera-streamer.deb" || apt-get -f install -y
  else
    echo "Falling back to source build for camera-streamer…"
    apt_install_norec \
      build-essential cmake meson ninja-build pkg-config \
      libevent-dev libmicrohttpd-dev libssl-dev libjpeg-dev libwebp-dev \
      libv4l-dev libdrm-dev libasound2-dev libx264-dev libopus-dev \
      libcamera-dev libfmt-dev

    git clone --depth=1 --recurse-submodules https://github.com/ayufan/camera-streamer.git /tmp/camera-streamer
    make -C /tmp/camera-streamer -j"$(nproc)"
    # Common output path in this repo is ./output/camera-streamer
    if [ -x /tmp/camera-streamer/output/camera-streamer ]; then
      install -D -m0755 /tmp/camera-streamer/output/camera-streamer /usr/local/bin/camera-streamer
    elif [ -x /tmp/camera-streamer/camera-streamer ]; then
      install -D -m0755 /tmp/camera-streamer/camera-streamer /usr/local/bin/camera-streamer
    else
      echo "camera-streamer binary not found after build"; exit 1
    fi
  fi

  # Health check (non-fatal)
  if command -v camera-streamer >/dev/null 2>&1; then camera-streamer --help >/dev/null || true; fi
}

# -------- OPi 5 family: ustreamer backend --------
install_ustreamer_stack() {
  apt_update_once
  if ! apt_install_norec ustreamer; then
    # Build from source if Debian package not present
    apt_install_norec build-essential git libevent-dev libjpeg-dev
    git clone --depth=1 https://github.com/pikvm/ustreamer.git /tmp/ustreamer
    make -C /tmp/ustreamer -j"$(nproc)"
    install -D -m0755 /tmp/ustreamer/ustreamer /usr/local/bin/ustreamer
  fi
  apt_install_norec v4l-utils
  # Quick probe
  if command -v ustreamer >/dev/null 2>&1; then ustreamer --help >/dev/null || true; fi
}

# -------- Main --------
case "$(arch)" in
  arm64|aarch64)
    if is_rpi; then
      echo "Detected Raspberry Pi (64-bit)."
      install_rpi_libcamera_stack
      # RPi5 needs the new libcamera/rpicam stack; camera-streamer uses libcamera path when needed.
      # Upstream recommends camera-streamer for Pi backends; Crowsnest should use `mode: camera-streamer`.
      # (Crowsnest docs show camera mode selection via [cam] section.)  # refs in header
      build_or_install_camera_streamer
    elif is_orangepi5; then
      echo "Detected Orange Pi 5 series."
      # Prefer ustreamer backend on RK3588; keep things simple and portable.
      install_ustreamer_stack
      echo "camera-streamer skipped on OPi5; configure Crowsnest cam with 'mode: ustreamer'."
    else
      # Generic 64-bit SBC fallback: prefer ustreamer (works with any V4L2 USB cam)
      echo "Unknown 64-bit SBC; installing generic V4L2 + ustreamer."
      install_ustreamer_stack
    fi
    ;;
  *)
    # Non-ARM or unexpected – don’t fail customize
    echo "Non-ARM or unknown arch ($(arch)); skipping camera backend install."
    ;;
esac

# No services enabled here. Crowsnest manages runtime.
# Print a brief summary so the CI log shows what we did.
echo "---- Camera backend summary ----"
command -v camera-streamer >/dev/null 2>&1 && echo "camera-streamer: $(camera-streamer --version 2>/dev/null || echo present)" || echo "camera-streamer: not installed"
command -v ustreamer      >/dev/null 2>&1 && echo "ustreamer: present" || echo "ustreamer: not installed"
command -v rpicam-hello   >/dev/null 2>&1 && echo "rpicam-apps: present" || echo "rpicam-apps: not installed"
command -v libcamera-hello>/dev/null 2>&1 && echo "libcamera-tools: present" || echo "libcamera-tools: not installed"
echo "--------------------------------"
