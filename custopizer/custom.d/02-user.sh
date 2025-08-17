#!/usr/bin/env bash
set -Eeuxo pipefail
export LC_ALL=C

source /common.sh
install_cleanup_trap
# Use helpers if present (scoped sudo, run-as-user, writers, etc.)
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

# --- Load persisted defaults (if set by a prior run) ---
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true

# --- Inputs / defaults ---
KS_USER="${KS_USER:-pi}"
KS_USER="${KS_USER,,}"  # normalize
KS_GROUPS="${KS_GROUPS:-sudo,dialout,tty,plugdev,video,render,input,gpio,i2c,spi}"
KS_SUDO_NOPASSWD="${KS_SUDO_NOPASSWD:-1}"
HOME_DIR="${HOME_DIR:-/home/${KS_USER}}"

# --- Ensure groups exist (idempotent) ---
IFS=',' read -r -a _groups <<<"$KS_GROUPS"
for g in "${_groups[@]}"; do
  [ -z "$g" ] && continue
  getent group "$g" >/dev/null 2>&1 || addgroup --system "$g" || addgroup "$g" || true
done

# --- Create or reconcile the user and home ---
if id -u "$KS_USER" >/dev/null 2>&1; then
  usermod -s /bin/bash -d "$HOME_DIR" "$KS_USER" || true
  for g in "${_groups[@]}"; do
    id -nG "$KS_USER" | tr ' ' '\n' | grep -qx "$g" || usermod -a -G "$g" "$KS_USER" || true
  done
  [ -d "$HOME_DIR" ] || install -d -o "$KS_USER" -g "$KS_USER" "$HOME_DIR"
else
  adduser --disabled-password --gecos "" --home "$HOME_DIR" --shell /bin/bash "$KS_USER"
  for g in "${_groups[@]}"; do usermod -a -G "$g" "$KS_USER" || true; done
fi
chown -R "$KS_USER:$KS_USER" "$HOME_DIR"

# --- Optional SSH key provisioning (KS_SSH_PUBKEY) ---
if [ -n "${KS_SSH_PUBKEY:-}" ]; then
  install -d -m 0700 -o "$KS_USER" -g "$KS_USER" "$HOME_DIR/.ssh"
  printf "%s\n" "$KS_SSH_PUBKEY" | install -D -m 0600 /dev/stdin "$HOME_DIR/.ssh/authorized_keys"
  chown "$KS_USER:$KS_USER" "$HOME_DIR/.ssh/authorized_keys"
fi

# --- Scoped passwordless sudo (only if requested) ---
if [ "$KS_SUDO_NOPASSWD" = "1" ]; then
  # Helper grants NOPASSWD for apt/systemctl/journalctl; safer than ALL:ALL
  if command -v ensure_sudo_nopasswd >/dev/null 2>&1; then
    ensure_sudo_nopasswd
  else
    install -d -m 0750 /etc/sudoers.d
    f="/etc/sudoers.d/010-${KS_USER}-nopasswd"
    cat >"$f" <<EOF
${KS_USER} ALL=(root) NOPASSWD:/usr/bin/apt,/usr/bin/apt-get,/usr/bin/systemctl,/usr/sbin/service,/usr/bin/journalctl
EOF
    chown 0:0 "$f"; chmod 0440 "$f"
  fi
fi

# --- Printer data layout (idempotent) ---
install -d -o "$KS_USER" -g "$KS_USER" "$HOME_DIR/printer_data/config"
install -d -o "$KS_USER" -g "$KS_USER" "$HOME_DIR/printer_data/logs"
install -d -o "$KS_USER" -g "$KS_USER" "$HOME_DIR/printer_data/gcodes"

# --- Persist for later scripts ---
cat >/etc/ks-user.conf <<EOF
KS_USER=${KS_USER}
HOME_DIR=${HOME_DIR}
KS_GROUPS=${KS_GROUPS}
KS_SUDO_NOPASSWD=${KS_SUDO_NOPASSWD}
export KS_USER HOME_DIR KS_GROUPS KS_SUDO_NOPASSWD
EOF

echo "[user] KS_USER=${KS_USER} HOME_DIR=${HOME_DIR} GROUPS=${KS_GROUPS} sudo_nopasswd=${KS_SUDO_NOPASSWD}"
