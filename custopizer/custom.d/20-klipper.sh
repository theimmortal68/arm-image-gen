#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

source /common.sh
install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

section "Install Klipper (KalicoCrew bleeding-edge-v2)"
apt_install git curl ca-certificates gcc g++ make libffi-dev pkg-config \
            libatlas3-base libatlas-base-dev libgfortran5 libjpeg-dev zlib1g-dev

ensure_venv /home/pi/klippy-env

# Clone/update Klipper (Kalico)
as_user "${KS_USER:-pi}" 'git_sync https://github.com/KalicoCrew/kalico "$HOME/klipper" bleeding-edge-v2 1'

# Minimal wheels (numpy/matplotlib used by some helpers; keep versions flexible)
pip_install /home/pi/klippy-env "numpy" "matplotlib" "cffi"

# Precompile Python once, single-threaded to avoid SemLock issues in chroot
as_user "${KS_USER:-pi}" 'cd "$HOME/klipper" && "$HOME/klippy-env/bin/python" -m compileall -q -j 1 klippy && "$HOME/klippy-env/bin/python" klippy/chelper/__init__.py'

# Update manager entry for Klipper (so it shows in Software Updates)
um_write_repo klipper "/home/pi/klipper" "https://github.com/KalicoCrew/kalico.git" "bleeding-edge-v2" "klipper"

# Systemd service enablement will be handled post-boot by moonraker installer; no-op here.
apt_clean_all
