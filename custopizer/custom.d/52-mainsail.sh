#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

source /common.sh
install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

section "Install Mainsail UI"
apt_install unzip curl ca-certificates
# Install to ~/mainsail (latest release)
as_user "${KS_USER:-pi}" '
  install -d "$HOME/mainsail"
  tmp="$(mktemp -d)"
  curl -fsSL "https://github.com/mainsail-crew/mainsail/releases/latest/download/mainsail.zip" -o "$tmp/mainsail.zip"
  unzip -o "$tmp/mainsail.zip" -d "$HOME/mainsail"
  rm -rf "$tmp"
'
apt_clean_all
