#!/usr/bin/env bash
set -Eeuxo pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap

# Load persisted/defaults
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true
KS_USER="${KS_USER:-pi}"
KS_USER="${KS_USER,,}"
KS_GROUPS="${KS_GROUPS:-sudo,dialout,tty,plugdev,video,render,input,gpio,i2c,spi}"
KS_SUDO_NOPASSWD="${KS_SUDO_NOPASSWD:-1}"
HOME_DIR="/home/${KS_USER}"

# Ensure groups
IFS=',' read -r -a _groups <<<"$KS_GROUPS"
for g in "${_groups[@]}"; do
  [ -z "$g" ] && continue
  getent group "$g" >/dev/null || addgroup --system "$g" || addgroup "$g" || true
done

# Create or reconcile user
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

# Sudo policy
if [ "$KS_SUDO_NOPASSWD" = "1" ]; then
  install -d -m 0755 /etc/sudoers.d
  f="/etc/sudoers.d/010-${KS_USER}-nopasswd"
  echo "${KS_USER} ALL=(ALL) NOPASSWD:ALL" >"$f"
  chown 0:0 "$f"; chmod 0440 "$f"
fi

# Persist for later scripts
cat >/etc/ks-user.conf <<EOF
KS_USER=${KS_USER}
HOME_DIR=${HOME_DIR}
KS_GROUPS=${KS_GROUPS}
export KS_USER HOME_DIR KS_GROUPS
EOF

echo "[user] KS_USER=${KS_USER} HOME_DIR=${HOME_DIR} GROUPS=${KS_GROUPS} sudo_nopasswd=${KS_SUDO_NOPASSWD}"
