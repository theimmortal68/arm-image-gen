#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

source /common.sh
install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

section "Install Moonraker Timelapse"
apt_install sudo git ffmpeg build-essential ca-certificates
ensure_sudo_nopasswd
create_systemctl_shim

# Clone/update installer
as_user "${KS_USER:-pi}" 'git_sync https://github.com/mainsail-crew/moonraker-timelapse.git "$HOME/moonraker-timelapse" main 1'

# Provide update-manager include (not editing moonraker.conf directly)
um_write_repo timelapse "/home/${KS_USER:-pi}/moonraker-timelapse" "https://github.com/mainsail-crew/moonraker-timelapse.git" "main" "klipper"

# Include macros
as_user "${KS_USER:-pi}" '
  CONF_DIR="$HOME/printer_data/config"
  SRC="$HOME/moonraker-timelapse/klipper_macro/timelapse.cfg"
  DST="$CONF_DIR/timelapse.cfg"
  install -d "$CONF_DIR"
  [ -f "$SRC" ] && [ ! -f "$DST" ] && cp "$SRC" "$DST" || true
  PRN="$CONF_DIR/printer.cfg"
  touch "$PRN"
'
ensure_include_line "/home/${KS_USER:-pi}/printer_data/config/printer.cfg" "[include timelapse.cfg]"

enable_at_boot moonraker-timelapse.service
remove_systemctl_shim
apt_clean_all
