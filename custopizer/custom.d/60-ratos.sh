#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh
install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

export DEBIAN_FRONTEND=noninteractive

section "RatOS integration (theme + installer running inside user venv)"

# Device user (guaranteed to exist per your build contract)
KS_USER="${IGconf_device_user1:-pi}"
HOME_DIR="$(getent passwd "$KS_USER" | cut -d: -f6 || true)"
[ -n "$HOME_DIR" ] || HOME_DIR="/home/${KS_USER}"

# --- Optional: RatOS theme (matches your prior flow) ---
# No idempotence checks by request: cloning into an existing dir will fail (desired).
RATOS_THEME_REPO="https://github.com/Rat-OS/RatOS-theme.git"
RATOS_THEME_REF="v2.1.x"       # adjust as needed
git_sync "${RATOS_THEME_REPO}" "${HOME_DIR}/RatOS-theme" "${RATOS_THEME_REF}" 1

# Register theme with Moonraker Update Manager (user-scope include).
# Keep managed_services empty (theme is static; no restart needed).
um_write_repo "ratos-theme" \
              '~/RatOS-theme' \
              "${RATOS_THEME_REPO}" \
              "${RATOS_THEME_REF}" \
              ''

# --- Ensure RatOS Python work happens in the USER'S venv ---
# We do not create the venv here if you prefer it elsewhere (e.g., 02-user.sh).
# If the venv doesn't exist, this will fail loudly (desired per your rules).
as_user "${KS_USER}" '
  set -euxo pipefail
  export PATH="$HOME/klippy-env/bin:$PATH"
  export PIP_DISABLE_PIP_VERSION_CHECK=1
  export PIP_NO_CACHE_DIR=1

  # Keep pip tooling up to date inside the user venv
  python -m pip install --upgrade pip wheel

  # Run RatOS installer (non-interactive if your script supports it).
  # Try common locations; if your repo uses one canonical path, keep only that call.
  if [ -x "$HOME/printer_data/config/RatOS/scripts/ratos-install.sh" ]; then
    bash "$HOME/printer_data/config/RatOS/scripts/ratos-install.sh"
  else
    bash "$HOME/printer_data/config/RatOS/install.sh"
  fi
'

# --- (Optional) If RatOS ships a requirements file you want pinned explicitly ---
# as_user "${KS_USER}" '
#   set -euxo pipefail
#   "$HOME/klippy-env/bin/pip" install -r "$HOME/printer_data/config/RatOS/requirements.txt"
# '

# NOTE:
# - No direct edits to moonraker.conf (we only write user-scope update-manager includes).
# - No systemctl enable/start here; 99-enable-units.sh is the single enablement point.
# - Data paths remain created in 02-user.sh, per your rules.
