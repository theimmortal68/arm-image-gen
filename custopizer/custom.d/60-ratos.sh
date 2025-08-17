#!/usr/bin/env bash
# 60-ratos.sh — RatOS theme + configurator integration (helper-ized, chroot-safe)
set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

source /common.sh; install_cleanup_trap
# Helpers: apt_install, as_user, wr_root, section, etc.
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh || true

section "RatOS integration (theme + configurator)"

# Repos/branches
: "${RATOS_THEME_URL:=https://github.com/Rat-OS/RatOS-theme.git}"
: "${RATOS_THEME_BRANCH:=v2.1.x}"
: "${RATOS_CONF_URL:=https://github.com/theimmortal68/RatOS-configurator.git}"
: "${RATOS_CONF_BRANCH:=v2.1.x-backport}"

# Target user/home
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

# Minimal deps (Node/npm expected from 12-nodejs-pnpm.sh; we don't install here)
apt_install git curl ca-certificates

# Ensure config dir exists and owned by user
install -d -o "${KS_USER}" -g "${KS_USER}" "${HOME_DIR}/printer_data/config"

# --- Clone/refresh RatOS Theme into printer config as ".theme"
as_user "${KS_USER}" '
  install -d "$HOME/printer_data/config"
  if [ ! -d "$HOME/printer_data/config/.theme/.git" ]; then
    git clone --depth=1 --branch "'"${RATOS_THEME_BRANCH}"'" "'"${RATOS_THEME_URL}"'" "$HOME/printer_data/config/.theme"
  else
    git -C "$HOME/printer_data/config/.theme" fetch --depth=1 origin "'"${RATOS_THEME_BRANCH}"'"
    git -C "$HOME/printer_data/config/.theme" reset --hard "origin/'"${RATOS_THEME_BRANCH}"'"
  fi
'

# --- Clone/refresh RatOS Configurator into ~/ratos-configurator
as_user "${KS_USER}" '
  if [ ! -d "$HOME/ratos-configurator/.git" ]; then
    git clone --depth=1 --branch "'"${RATOS_CONF_BRANCH}"'" "'"${RATOS_CONF_URL}"'" "$HOME/ratos-configurator"
  else
    git -C "$HOME/ratos-configurator" fetch --depth=1 origin "'"${RATOS_CONF_BRANCH}"'"
    git -C "$HOME/ratos-configurator" reset --hard "origin/'"${RATOS_CONF_BRANCH}"'"
  fi
  git config --global pull.ff only
'

# --- Create a release file (Moonraker/distro detection friendliness)
codename="$(awk -F= '/^VERSION_CODENAME=/{print $2}' /etc/os-release || true)"
: "${codename:=unknown}"
printf 'KlipperSuite v%s (%s)\n' "$(date -u +%Y.%m.%d)" "${codename}" | wr_root 0644 /etc/klippersuite-release

# Workarounds for distro detection quirks (first-file-wins in some UIs)
[ -f /etc/armbian-release ]  && ln -sf /etc/klippersuite-release /etc/aaaa-release
[ -f /etc/orangepi-release ] && ln -sf /etc/klippersuite-release /etc/aaaa-release

# --- Run RatOS Configurator setup (prepares node deps etc.)
as_user "${KS_USER}" 'bash "$HOME/ratos-configurator/app/scripts/setup.sh"'

# --- Optionally start the configurator (best-effort) for API access
# In chroot, services aren't running; we only start a transient dev server if npm exists.
as_user "${KS_USER}" '
  if command -v npm >/dev/null 2>&1; then
    cd "$HOME/ratos-configurator/app"
    ( npm run start --silent >/dev/null 2>&1 & echo $! > "$HOME/.ratos-configurator.pid" ) || true
  else
    echo "[ratos] npm not found; skipping transient dev server start" >&2
  fi
'

# Wait until the app responds with HTTP 404 on / (readiness) — best-effort
timeout 180 bash -c 'while pid="$(cat "/home/'"${KS_USER}"'/.ratos-configurator.pid" 2>/dev/null)"; do
  code="$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3000 || echo 000)"
  [ "$code" = "404" ] && exit 0
  sleep 3
done; exit 0' || true

# --- Preflight: ensure Klippy venv is user-owned & on PATH so RatOS pip installs succeed
VENV_DIR="${HOME_DIR}/klippy-env"
if [ -d "${VENV_DIR}" ]; then
  chown -R "${KS_USER}:${KS_USER}" "${VENV_DIR}"
fi

# --- Run RatOS printer configuration installer (user-level)
# Ensure the venv's bin precedes system python/pip so the installer uses it.
as_user "${KS_USER}" '
  export PATH="$HOME/klippy-env/bin:$PATH"
  export PIP_DISABLE_PIP_VERSION_CHECK=1
  export PIP_NO_CACHE_DIR=1
  bash "$HOME/printer_data/config/RatOS/scripts/ratos-install.sh" || true
'

# --- Variant marker (informational)
variant="debian"
[ -f /etc/armbian-release ]  && variant="armbian"
[ -f /etc/orangepi-release ] && variant="orangepi"
printf '%s\n' "${variant}" | wr_root 0644 "/etc/${variant}-variant"

# --- MOTD: if a prebuilt block is provided in /files/motd.ratos, install it
if [ -r /files/motd.ratos ]; then
  install -D -m 0644 /files/motd.ratos /etc/motd
fi

# --- Post-install (best-effort)
as_user "${KS_USER}" 'bash "$HOME/printer_data/config/RatOS/scripts/ratos-post-install.sh" || true'

# --- Stop the transient configurator if we started it
set +e
curl -s 'http://127.0.0.1:3000/configure/api/trpc/kill' >/dev/null 2>&1
set -e
as_user "${KS_USER}" '
  if [ -f "$HOME/.ratos-configurator.pid" ]; then
    pid="$(cat "$HOME/.ratos-configurator.pid" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" || true
      sleep 2
      kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$HOME/.ratos-configurator.pid"
  fi
'

echo_green "[ratos] Theme + Configurator installed and basic scripts executed"
apt_clean_all
