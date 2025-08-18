#!/usr/bin/env bash
# 30-moonraker.sh — Install Moonraker in a CustoPiZer chroot
set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

# Base bootstrap
source /common.sh
install_cleanup_trap
# Optional helper library
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

section() { echo; echo "=== $* ==="; }
echo_green() { echo "[OK] $*"; }
echo_yellow() { echo "[WARN] $*"; }
echo_red() { echo "[ERR] $*" >&2; }

# Run a command as the target user; re-source helpers inside the child shell
as_user() {
  local u="$1"; shift
  local cmd="$*"
  runuser -u "$u" -- bash -lc "set -euxo pipefail; [ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh || true; $cmd"
}

# Resolve target user/home (persisted by your 02-user.sh)
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

section "Ensure ~/printer_data is present and owned by ${KS_USER}"
install -d -o "${KS_USER}" -g "${KS_USER}" "${HOME_DIR}/printer_data"
install -d -o "${KS_USER}" -g "${KS_USER}" "${HOME_DIR}/printer_data/config"
chown -R "${KS_USER}:${KS_USER}" "${HOME_DIR}/printer_data"

section "Clone or refresh Moonraker (as ${KS_USER})"
as_user "${KS_USER}" '
  if [ ! -d "$HOME/moonraker/.git" ]; then
    git clone --depth=1 https://github.com/Arksine/moonraker.git "$HOME/moonraker"
  else
    git -C "$HOME/moonraker" fetch --depth=1 origin
    # Use whatever the default remote HEAD is
    def_branch="$(git -C "$HOME/moonraker" rev-parse --abbrev-ref origin/HEAD | sed "s@^origin/@@")" || def_branch=master
    git -C "$HOME/moonraker" reset --hard "origin/${def_branch}"
  fi
'

section "Run Moonraker installer (as ${KS_USER}, systemctl disabled)"
as_user "${KS_USER}" '
  cd "$HOME/moonraker"
  MOONRAKER_DISABLE_SYSTEMCTL=1 ./scripts/install-moonraker.sh -f -c "$HOME/printer_data/config/moonraker.conf"
'

# (Optional) Drop an Update Manager entry; Moonraker can manage itself, but harmless if present
# as_user "${KS_USER}" '
#   CONF_DIR="$HOME/printer_data/config/update-manager.d"; install -d "$CONF_DIR"
#   cat >"$CONF_DIR/moonraker.conf" <<EOF
# [update_manager moonraker]
# type: git_repo
# path: ~/moonraker
# origin: https://github.com/Arksine/moonraker.git
# primary_branch: master
# managed_services: moonraker
# EOF
# '

echo_green "[moonraker] installation complete (chroot-safe)."
