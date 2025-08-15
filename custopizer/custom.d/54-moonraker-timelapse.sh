#!/usr/bin/env bash
set -Eeuo pipefail
set -x
export LC_ALL=C
# shellcheck disable=SC1091
source /common.sh; install_cleanup_trap
export DEBIAN_FRONTEND=noninteractive

# --- Discover user/home (from 02-user.sh) -------------------------------------
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true
KS_USER="${KS_USER:-pi}"
HOME_DIR="$(getent passwd "${KS_USER}" | cut -d: -f6 || true)"
HOME_DIR="${HOME_DIR:-/home/${KS_USER}}"

REPO_URL="https://github.com/mainsail-crew/moonraker-timelapse.git"
SRC_DIR="${HOME_DIR}/moonraker-timelapse"
MOONRAKER_SRC_DIR="${HOME_DIR}/moonraker"                       # source checkout layout
MOONRAKER_COMPONENTS_PATH="${MOONRAKER_SRC_DIR}/moonraker/components"
PRINTER_CONFIG_PATH="${HOME_DIR}/printer_data/config"
TIMELAPSE_COMPONENT_REL="component/timelapse.py"
TIMELAPSE_MACRO_REL="klipper_macro/timelapse.cfg"

# --- Dependencies --------------------------------------------------------------
apt-get update || true
apt-get install -y --no-install-recommends git ffmpeg || true

# --- Ensure base paths exist (don’t hard-fail if Moonraker layout differs) -----
install -d -o "${KS_USER}" -g "${KS_USER}" "${HOME_DIR}"
install -d -o "${KS_USER}" -g "${KS_USER}" "${PRINTER_CONFIG_PATH}"
# Only create components dir if Moonraker source tree exists
if [ -d "${MOONRAKER_SRC_DIR}/moonraker" ]; then
  install -d -o "${KS_USER}" -g "${KS_USER}" "${MOONRAKER_COMPONENTS_PATH}"
fi

# --- Clone/refresh timelapse repo ---------------------------------------------
if [ ! -d "${SRC_DIR}/.git" ]; then
  runuser -u "${KS_USER}" -- git clone --depth=1 "${REPO_URL}" "${SRC_DIR}"
else
  runuser -u "${KS_USER}" -- git -C "${SRC_DIR}" fetch --depth=1 origin || true
  runuser -u "${KS_USER}" -- git -C "${SRC_DIR}" reset --hard origin/HEAD || true
fi
chown -R "${KS_USER}:${KS_USER}" "${SRC_DIR}"

# --- Link Moonraker component (if source-tree layout is present) ---------------
if [ -d "${MOONRAKER_COMPONENTS_PATH}" ] && [ -f "${SRC_DIR}/${TIMELAPSE_COMPONENT_REL}" ]; then
  ln -sf "${SRC_DIR}/${TIMELAPSE_COMPONENT_REL}" "${MOONRAKER_COMPONENTS_PATH}/timelapse.py"
  chown -h "${KS_USER}:${KS_USER}" "${MOONRAKER_COMPONENTS_PATH}/timelapse.py" || true
  echo "[timelapse] linked component → ${MOONRAKER_COMPONENTS_PATH}/timelapse.py"
else
  echo "[timelapse] Moonraker source components dir not found; skipping component symlink (OK if Moonraker runs from venv/package)."
fi

# --- Link Klipper macro into printer config -----------------------------------
if [ -f "${SRC_DIR}/${TIMELAPSE_MACRO_REL}" ]; then
  ln -sf "${SRC_DIR}/${TIMELAPSE_MACRO_REL}" "${PRINTER_CONFIG_PATH}/timelapse.cfg"
  chown -h "${KS_USER}:${KS_USER}" "${PRINTER_CONFIG_PATH}/timelapse.cfg" || true
  echo "[timelapse] linked macro → ${PRINTER_CONFIG_PATH}/timelapse.cfg"
fi

# --- Add config to moonraker.conf ---------------------------------------------
MOONRAKER_CONF="${PRINTER_CONFIG_PATH}/moonraker.conf"
touch "${MOONRAKER_CONF}"
chown "${KS_USER}:${KS_USER}" "${MOONRAKER_CONF}"

# Minimal [timelapse] section (idempotent)
if ! grep -q '^\[timelapse\]' "${MOONRAKER_CONF}"; then
  cat >>"${MOONRAKER_CONF}" <<'EOF'

[timelapse]
# Basic defaults; tune in UI later
ffmpeg_binary_path: /usr/bin/ffmpeg
EOF
else
  # Ensure ffmpeg path present
  awk '
    BEGIN{in=0;have=0}
    /^\[timelapse\]/{in=1}
    in && /^ffmpeg_binary_path:/{have=1}
    in && /^\[/{in=0}
    {print}
    END{ if(!have){ print "ffmpeg_binary_path: /usr/bin/ffmpeg" } }
  ' "${MOONRAKER_CONF}" > "${MOONRAKER_CONF}.tmp" && mv -f "${MOONRAKER_CONF}.tmp" "${MOONRAKER_CONF}"
fi

# Optional: Update Manager block so UI can update timelapse repo
if ! grep -q '^\[update_manager timelapse\]' "${MOONRAKER_CONF}"; then
  cat >>"${MOONRAKER_CONF}" <<EOF

[update_manager timelapse]
type: git_repo
path: ${SRC_DIR}
origin: ${REPO_URL}
primary_branch: main
managed_services: klipper moonraker
EOF
fi

# --- Ownership -----------------------------------------------------------------
chown -R "${KS_USER}:${KS_USER}" "${PRINTER_CONFIG_PATH}" || true

echo "[timelapse] setup complete"
# No systemctl start here (chroot). 99-enable-units handles wants/ on first boot (if any).
