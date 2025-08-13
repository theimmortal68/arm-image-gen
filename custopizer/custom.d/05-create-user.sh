#!/bin/bash
set -x
set -e
export LC_ALL=C
source /common.sh; install_cleanup_trap

# Prefer value from 00-detect-user.sh; if missing, auto-detect/fallback.
if [ -f /etc/ks-user.conf ]; then
  . /etc/ks-user.conf
fi
KS_USER="${KS_USER:-}"

if [ -z "$KS_USER" ]; then
  for u in pi ubuntu debian armbian orangepi; do
    if getent passwd "$u" >/dev/null 2>&1; then KS_USER="$u"; break; fi
  done
  KS_USER="${KS_USER:-pi}"
  echo "KS_USER=${KS_USER}" >/etc/ks-user.conf
fi

# Optional public key injection via env
KS_SSH_PUBKEY="${KS_SSH_PUBKEY:-}"

# Ensure user exists
if ! id -u "$KS_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$KS_USER"
fi

# Add helpful groups if present on this base
for g in sudo adm dialout tty plugdev video input render gpio; do
  getent group "$g" >/dev/null 2>&1 && usermod -aG "$g" "$KS_USER" || true
done

HOME_DIR="$(getent passwd "$KS_USER" | cut -d: -f6)"
[ -n "$HOME_DIR" ] || { echo_red "[create-user] could not resolve home for $KS_USER"; exit 1; }

# Create Klipper data dirs
install -d -o "$KS_USER" -g "$KS_USER" \
  "$HOME_DIR/printer_data/config" \
  "$HOME_DIR/printer_data/logs" \
  "$HOME_DIR/bin"

# Passwordless sudo (optional; easy to tighten later)
cat >/etc/sudoers.d/010-${KS_USER}-nopasswd <<EOF
${KS_USER} ALL=(ALL) NOPASSWD:ALL
EOF
chmod 0440 /etc/sudoers.d/010-${KS_USER}-nopasswd

# Seed authorized_keys if provided
if [ -n "$KS_SSH_PUBKEY" ]; then
  install -d -m 0700 -o "$KS_USER" -g "$KS_USER" "$HOME_DIR/.ssh"
  echo "$KS_SSH_PUBKEY" >>"$HOME_DIR/.ssh/authorized_keys"
  chown "$KS_USER:$KS_USER" "$HOME_DIR/.ssh/authorized_keys"
  chmod 0600 "$HOME_DIR/.ssh/authorized_keys"
  echo_green "[create-user] added SSH public key for $KS_USER"
fi

echo_green "[create-user] ensured user=$KS_USER, groups and directories ready"
