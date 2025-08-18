#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh
install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

export DEBIAN_FRONTEND=noninteractive

section "RatOS integration (theme, configurator, install, post-install)"

# --- Device/user context ---
KS_USER="${IGconf_device_user1:-pi}"
HOME_DIR="$(getent passwd "$KS_USER" | cut -d: -f6 || true)"
[ -n "$HOME_DIR" ] || HOME_DIR="/home/${KS_USER}"

# --- Config (clean names; override via environment if desired) ---
: "${RATOS_THEME_REPO:=https://github.com/Rat-OS/RatOS-theme.git}"
: "${RATOS_THEME_BRANCH:=v2.1.x}"
: "${RATOS_CONFIGURATOR_REPO:=https://github.com/theimmortal68/RatOS-configurator.git}"
: "${RATOS_CONFIGURATOR_BRANCH:=v2.1.x-backport}"
# python3-serial (klipper req), python3-opencv (obico req)
: "${RATOS_DEPS:=python3-serial python3-opencv}"

# --- A) Clone theme and configurator (no idempotence checks by design) ---
section "Clone RatOS theme and configurator"
as_user "${KS_USER}" "
  set -euxo pipefail
  cd \"${HOME_DIR}/printer_data/config\"
  git clone --depth=1 --branch \"${RATOS_THEME_BRANCH}\" \"${RATOS_THEME_REPO}\" .theme
"
as_user "${KS_USER}" "
  set -euxo pipefail
  cd \"${HOME_DIR}\"
  git clone --depth=1 --branch \"${RATOS_CONFIGURATOR_BRANCH}\" \"${RATOS_CONFIGURATOR_REPO}\" ratos-configurator
"

# --- B) Git config: fast-forward only (for the user) ---
as_user "${KS_USER}" '
  set -euxo pipefail
  git config --global pull.ff only
'

# --- C) Distro release stamping & Moonraker-friendly alias ---
DIST_NAME="${DIST_NAME:-arm-image-gen}"
DIST_VERSION="${DIST_VERSION:-dev}"
get_parent() { . /etc/os-release; echo "${VERSION_CODENAME:-unknown}"; }

echo "${DIST_NAME} v${DIST_VERSION} ($(get_parent))" > "/etc/${DIST_NAME,,}-release"

# Workaround for Armbian/OrangePi: make sure Moonraker's 'distro' sees us first
if [ -f "/etc/armbian-release" ]; then
  ln -sf "/etc/${DIST_NAME,,}-release" /etc/aaaa-release
fi
if [ -f "/etc/orangepi-release" ]; then
  ln -sf "/etc/${DIST_NAME,,}-release" /etc/aaaa-release
fi

# --- D) System deps used by RatOS (kept here per reference workflow) ---
section "Install RatOS system deps"
apt-get update --allow-releaseinfo-change
# Provided by /common.sh in upstream refs; no quotes on purpose to allow word-splitting
# shellcheck disable=SC2086
check_install_pkgs ${RATOS_DEPS}

# --- E) Configurator setup, start, and wait for API (HTTP 404 = ready) ---
section "Install RatOS Configurator (app/scripts/setup.sh)"
as_user "${KS_USER}" "
  set -euxo pipefail
  bash \"${HOME_DIR}/ratos-configurator/app/scripts/setup.sh\"
"

section "Start RatOS Configurator and wait for API to come up"
as_user "${KS_USER}" "
  set -euxo pipefail
  cd \"${HOME_DIR}/ratos-configurator/app\"
  npm run start &
"
# Wait up to 5 minutes; 404 indicates the TRPC endpoint is alive and serving
timeout 300 bash -c 'while [ "$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000)" != "404" ]; do sleep 5; done' || true

echo "RATOS CLI SANITY CHECKS"
echo "$PATH"
ls -la /usr/local/bin

# --- F) Run RatOS installer inside the USER venv (no system pip) ---
section "Run RatOS installer (inside user klippy-env)"
as_user "${KS_USER}" '
  set -euxo pipefail
  export PATH="$HOME/klippy-env/bin:$PATH"
  export PIP_DISABLE_PIP_VERSION_CHECK=1
  export PIP_NO_CACHE_DIR=1

  if [ -x "$HOME/printer_data/config/RatOS/scripts/ratos-install.sh" ]; then
    bash "$HOME/printer_data/config/RatOS/scripts/ratos-install.sh"
  else
    bash "$HOME/printer_data/config/RatOS/install.sh"
  fi
'

# --- G) Variant stamp (like reference) ---
BASE_DISTRO="${BASE_DISTRO:-$(
  . /etc/os-release
  echo "${ID:-debian}"
)}"
echo "${BASE_DISTRO}" > "/etc/${BASE_DISTRO}-variant"

# --- H) MOTD banner is now staged in /files/etc by 15-stage-files.sh ---
section "MOTD handled by 15-stage-files.sh (custopizer/files/etc/motd)"

# --- I) Post-install: stop configurator & debug dump ---
section "RatOS post-install: stop configurator and cleanup"

as_user "${KS_USER}" "
  set -euxo pipefail
  bash \"${HOME_DIR}/printer_data/config/RatOS/scripts/ratos-post-install.sh\"
"

# Graceful stop via API; ignore errors then fall back to kill
set +e
curl 'http://localhost:3000/configure/api/trpc/kill' >/dev/null 2>&1 || true
set -e

retries=0
while pgrep -f -c "ratos-configurator" >/dev/null; do
  if [ "${retries}" -gt 10 ]; then
    pkill -f "ratos-configurator" || true
    [ "${retries}" -gt 12 ] && break
  fi
  sleep 1
  retries=$((retries+1))
done

ps aux || true

# NOTES:
# - No systemctl enable/start here; 99-enable-units.sh is the single enablement point.
# - All Python installs run inside the user's klippy-env.
# - MOTD is provided via staged file under /files/etc/motd.
