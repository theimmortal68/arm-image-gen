#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

source /common.sh
install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

section "Install camera streaming backend(s)"
# Favor ustreamer (works broadly); keep ffmpeg around for tools
apt_install ustreamer ffmpeg v4l-utils

# Example crowsnest conf shipped separately; nothing else to do here.
apt_clean_all
