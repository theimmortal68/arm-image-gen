#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh; install_cleanup_trap

# RatOS integration (theme + configurator + install scripts) + overlay
#   Theme:        https://github.com/Rat-OS/RatOS-theme.git (v2.1.x)
#   Configurator: https://github.com/theimmortal68/RatOS-configurator.git (v2.1.x-backport)

RATOS_THEME_URL="https://github.com/Rat-OS/RatOS-theme.git"
RATOS_THEME_BRANCH="v2.1.x"
RATOS_CONF_URL="https://github.com/theimmortal68/RatOS-configurator.git"
RATOS_CONF_BRANCH="v2.1.x-backport"

# Target user/home
# shellcheck disable=SC1091
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

export DEBIAN_FRONTEND=noninteractive

echo_green "Installing RatOS components (theme + configurator)"

# Minimal deps (Node/npm come from your 12-nodejs-pnpm.sh)
apt-get update
apt-get install -y --no-install-recommends git curl ca-certificates

# Ensure config dir exists
install -d -o "${KS_USER}" -g "${KS_USER}" "${HOME_DIR}/printer_data/config"

# --- Clone RatOS Theme into printer config as ".theme"
runuser -u "${KS_USER}" -- bash -lc "
  set -euo pipefail
  cd '${HOME_DIR}/printer_data/config'
  git clone --depth=1 --branch '${RATOS_THEME_BRANCH}' '${RATOS_THEME_URL}' .theme
"

# --- Clone RatOS Configurator into ~/ratos-configurator
runuser -u "${KS_USER}" -- bash -lc "
  set -euo pipefail
  cd '${HOME_DIR}'
  git clone --depth=1 --branch '${RATOS_CONF_BRANCH}' '${RATOS_CONF_URL}' ratos-configurator
"

# Fast-forward only on pull for the user
runuser -u "${KS_USER}" -- git config --global pull.ff only

# --- Create a release file (Moonraker/distro detection friendliness)
codename="$(awk -F= '/^VERSION_CODENAME=/{print $2}' /etc/os-release || true)"
: "${codename:=unknown}"
printf 'KlipperSuite v%s (%s)\n' "$(date -u +%Y.%m.%d)" "${codename}" > /etc/klippersuite-release

# Workaround for armbian/orangepi (Moonraker/distro “first file wins” quirk)
[ -f /etc/armbian-release ]  && ln -sf /etc/klippersuite-release /etc/aaaa-release
[ -f /etc/orangepi-release ] && ln -sf /etc/klippersuite-release /etc/aaaa-release

# --- Run RatOS Configurator setup
runuser -u "${KS_USER}" -- bash -lc "bash '${HOME_DIR}/ratos-configurator/app/scripts/setup.sh'"

# --- Start the configurator (background) for API access during install
echo "Starting RatOS Configurator"
runuser -u "${KS_USER}" -- bash -lc "
  set -euo pipefail
  cd '${HOME_DIR}/ratos-configurator/app'
  npm run start &
  echo \$! > '${HOME_DIR}/.ratos-configurator.pid'
"

# Wait until the app responds with HTTP 404 on / (readiness) — best-effort
timeout 300 bash -c 'while [ "$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3000)" != "404" ]; do sleep 5; done' || true

echo "RATOS CLI SANITY CHECKS"
echo "$PATH"
ls -la /usr/local/bin || true

# --- Run RatOS printer configuration installer (user-level)
runuser -u "${KS_USER}" -- bash -lc "bash '${HOME_DIR}/printer_data/config/RatOS/scripts/ratos-install.sh'"

# --- Variant marker (informational)
variant="debian"
[ -f /etc/armbian-release ]  && variant="armbian"
[ -f /etc/orangepi-release ] && variant="orangepi"
echo "${variant}" > "/etc/${variant}-variant"

# --- MOTD: keep your RatOS ASCII art block verbatim (same as original script)
# (Paste the full block you provided below)
cat > /etc/motd << 'EOF'
<PUT YOUR FULL ASCII ART BLOCK HERE>
EOF

# --- Post-install
runuser -u "${KS_USER}" -- bash -lc "bash '${HOME_DIR}/printer_data/config/RatOS/scripts/ratos-post-install.sh'"

# --- Stop the configurator cleanly via API, then ensure it exits
set +e
curl -s 'http://127.0.0.1:3000/configure/api/trpc/kill' >/dev/null 2>&1
set -e

retries=0
while pgrep -f -u "${KS_USER}" -c "ratos-configurator" >/dev/null 2>&1; do
  if [ "${retries}" -gt 10 ]; then
    echo "Configurator did not stop, killing it..."
    pkill -f -u "${KS_USER}" "ratos-configurator" || true
    if [ "${retries}" -gt 12 ]; then
      echo "Configurator cannot be killed.. :("
      break
    fi
  fi
  echo "Waiting for configurator to stop... ${retries}s passed"
  sleep 1
  retries=$((retries + 1))
done

echo_green "RatOS integration complete"
