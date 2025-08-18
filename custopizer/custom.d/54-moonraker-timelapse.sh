#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh
install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

export DEBIAN_FRONTEND=noninteractive

section "Install Moonraker Timelapse (non-interactive, ks_helpers-native)"

# Device user (guaranteed to exist before customize hooks)
USER_NAME="${IGconf_device_user1:-pi}"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6 || true)"
[ -n "$USER_HOME" ] || USER_HOME="/home/${USER_NAME}"

# Clone/update repo as the device user
git_sync "https://github.com/mainsail-crew/moonraker-timelapse.git" \
         "${USER_HOME}/moonraker-timelapse" \
         "main" 1

# Register with Moonraker Update Manager via helper.
# IMPORTANT: pass a LITERAL "~" path so the include shows "path: ~/moonraker-timelapse"
# Services: both klipper and moonraker as requested.
um_write_repo "timelapse" \
              '~/moonraker-timelapse' \
              'https://github.com/mainsail-crew/moonraker-timelapse.git' \
              'main' \
              'klipper moonraker'

# Seed a default timelapse.cfg if the user doesn't already have one
as_user "${USER_NAME}" '
  set -euxo pipefail
  CONF_DIR="$HOME/printer_data/config"
  SRC="$HOME/moonraker-timelapse/klipper_macro/timelapse.cfg"
  DST="$CONF_DIR/timelapse.cfg"
  install -d "$CONF_DIR"
  [ -f "$SRC" ] && [ ! -f "$DST" ] && cp -a "$SRC" "$DST" || true
'

# No service starts/enables here; 99-enable-units.sh is the single point of enablement.
