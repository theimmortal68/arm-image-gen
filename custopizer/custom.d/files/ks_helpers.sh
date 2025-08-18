# /files/ks_helpers.sh
# Extra helpers for CustoPiZer scripts (source *after* /common.sh)
# Safe to use with: set -euo pipefail

########################################
# Logging / guardrails
########################################
section() { echo; echo "=== $* ==="; }
die() { echo "ERROR: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

# Detect target user (CustoPiZer creates/exports KS_USER in your flow)
USER_NAME="${KS_USER:-pi}"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6 || true)"
[ -n "$USER_HOME" ] || USER_HOME="/home/$USER_NAME"

########################################
# APT helpers (idempotent)
########################################
_apt_updated=0
apt_update_once() { [ $_apt_updated -eq 1 ] || { apt-get update; _apt_updated=1; }; }

pkg_installed() { dpkg -s "$1" >/dev/null 2>&1; }
apt_install() { 
  apt_update_once
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}
apt_clean_all() { rm -rf /var/lib/apt/lists/*; }

########################################
# Sudoers / NOPASSWD for the target user
########################################
ensure_sudo_nopasswd() {
  apt_install sudo
  install -d -m 0750 -o root -g root /etc/sudoers.d
  install -D -m 0440 /dev/stdin "/etc/sudoers.d/010_${USER_NAME}-nopasswd" <<EOF
${USER_NAME} ALL=(ALL:ALL) NOPASSWD:ALL
EOF
}

########################################
# Run-as-user wrapper
########################################
as_user() {
  local u="$1"; shift
  local cmd="$*"
  runuser -u "$u" -- bash -lc \
    "set -euxo pipefail; [ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh; $cmd"
}

########################################
# Git: clone or fast reset to branch
########################################
git_sync() {
  # Usage: git_sync <repo_url> <dest_dir> [branch] [depth]
  local repo="$1" dest="$2" branch="${3:-main}" depth="${4:-1}"
  if [ ! -d "$dest/.git" ]; then
    git clone --depth="$depth" --branch "$branch" "$repo" "$dest"
  else
    git -C "$dest" fetch --depth="$depth" origin "$branch"
    git -C "$dest" reset --hard "origin/$branch"
  fi
}

########################################
# Python venv + compileall (no multiprocessing in chroot)
########################################
ensure_venv() { 
  local venv="$1"
  apt_install python3-venv python3-dev build-essential
  [ -d "$venv" ] || python3 -m venv "$venv"
  "$venv/bin/python" -m pip -q install --upgrade pip wheel setuptools
}
pip_install() { local venv="$1"; shift; "$venv/bin/python" -m pip install "$@"; }
py_compile_tree() { 
  # Use -j 1 (single process) to avoid ProcessPool semaphore errors in chroot
  local venv="$1" path="$2"
  "$venv/bin/python" -m compileall -q -j 1 "$path"
}

########################################
# systemctl shim for chrooted installers
########################################
create_systemctl_shim() {
  install -D -m 0755 /dev/stdin /usr/local/sbin/systemctl <<'EOF'
#!/usr/bin/env bash
# Chroot-safe systemctl shim: only use real systemctl if PID 1 is systemd
if [ -x /bin/systemctl ] && [ -r /proc/1/comm ] && grep -qx 'systemd' /proc/1/comm 2>/dev/null; then
  exec /bin/systemctl "$@"
fi
# No systemd: pretend success for common operations
case "$1" in
  enable|disable|daemon-reload|is-enabled|start|stop|restart|reload|status) exit 0 ;;
  *) exit 0 ;;
esac
EOF
}
remove_systemctl_shim() { rm -f /usr/local/sbin/systemctl; }

########################################
# Idempotent service enable (no-op in chroot)
########################################
enable_at_boot() {
  local unit="$1"
  if [ -f "/etc/systemd/system/$unit" ]; then
    install -d -m 0755 /etc/systemd/system/multi-user.target.wants
    ln -sf "../$unit" "/etc/systemd/system/multi-user.target.wants/$unit"
  fi
}

########################################
# Safe file writers (no nested heredocs inside runuser)
########################################
wr_root() { # wr_root <mode> <path>  ; read content from stdin
  local mode="$1" dst="$2"; shift 2 || true
  install -D -m "$mode" /dev/stdin "$dst"
}
wr_pi() {   # wr_pi <mode> </home/pi/...> ; read content from stdin
  local mode="$1" dst="$2"; shift 2 || true
  install -D -m "$mode" /dev/stdin "$dst"
  chown "$USER_NAME:$USER_NAME" "$dst" || true
}

########################################
# Moonraker update-manager.d drop-ins
########################################
um_write_repo() {
  local name="$1" lpath="$2" origin="$3" branch="${4:-main}" services="${5:-}"
  local dir="$USER_HOME/printer_data/config/update-manager.d"
  install -d "$dir"
  chown "$USER_NAME:$USER_NAME" "$dir"              # ★ ensure dir is owned by the user
  local um="$dir/$name.conf"
  cat >"$um" <<EOF
[update_manager $name]
type: git_repo
path: $lpath
origin: $origin
primary_branch: $branch
${services:+managed_services: $services}
EOF
  chown "$USER_NAME:$USER_NAME" "$um" || true
}

########################################
# Include helper for printer.cfg (idempotent)
########################################
ensure_include_line() {
  # Usage: ensure_include_line <file> "<line>"
  local f="$1" line="$2"
  touch "$f"
  grep -qxF "$line" "$f" || echo "$line" >> "$f"
}

########################################
# Kernel modules (avoid modprobe in chroot)
########################################
modules_load_dropin() {
  # Usage: modules_load_dropin <name.conf> "line1\nline2\n..."
  local name="$1" body="$2"
  local dst="/etc/modules-load.d/$name"
  printf "%b" "$body" | wr_root 0644 "$dst"
}


# /files/ks_helpers.sh (append)
fix_sudoers_sane() {
  install -d -m 0750 -o root -g root /etc/sudoers.d
  chown root:root /etc/sudoers.d
  # Fix any pre-existing files (e.g., README) so sudo will run
  find /etc/sudoers.d -type f -exec chown root:root {} \; -exec chmod 0440 {} \; || true
}

ensure_sudo_nopasswd_all() {
  fix_sudoers_sane
  install -D -m 0440 /dev/stdin "/etc/sudoers.d/999-custopizer-pi-all" <<'EOF'
pi ALL=(ALL) NOPASSWD:ALL
EOF
}
# End of ks_helpers.sh

# --- systemctl shim lifecycle (chroot-only) ---

ks_systemctl_shim_install() {
  set -euxo pipefail
  # Ensure /usr merge semantics cover /bin/systemctl as well.
  install -m 0755 /files/systemctl /usr/bin/systemctl

  # Optional: belt-and-suspenders to stop invoke-rc.d from starting services.
  # Comment out if you prefer strictly the shim approach.
  cat >/usr/sbin/policy-rc.d <<'EOF'
#!/bin/sh
# Prevent service starts in chroot; exit code 101 makes invoke-rc.d a no-op.
exit 101
EOF
  chmod +x /usr/sbin/policy-rc.d
}

ks_systemctl_shim_remove() {
  set -euxo pipefail
  # Remove shim and let the real systemctl (from systemd package) take its place at runtime.
  # If systemd isn’t installed yet in the chroot, this will simply leave no systemctl;
  # that’s fine, because enablement happens later on first boot.
  if [ -f /usr/bin/systemctl ]; then
    # Remove only if it's our shim (best-effort; we keep it simple per your rules)
    rm -f /usr/bin/systemctl
  fi

  # Clean up policy-rc.d if we created it
  rm -f /usr/sbin/policy-rc.d || true
}
