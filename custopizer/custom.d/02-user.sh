#!/usr/bin/env bash
set -Eeuxo pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap

# --- Inputs / precedence -------------------------------------------------------
# 1) Environment (KS_USER, KS_GROUPS, KS_SUDO_NOPASSWD)
# 2) Existing /etc/ks-user.conf (if present)
# 3) Defaults (pi, common groups, sudo NOPASSWD on)

# Load prior choice if env not set yet
if [ -z "${KS_USER:-}" ] && [ -f /etc/ks-user.conf ]; then
  # shellcheck disable=SC1091
  . /etc/ks-user.conf
fi

KS_USER="${KS_USER:-pi}"
KS_USER="${KS_USER,,}"  # lowercase
KS_GROUPS="${KS_GROUPS:-sudo,dialout,tty,plugdev,video,render,input,gpio,i2c,spi}"
KS_SUDO_NOPASSWD="${KS_SUDO_NOPASSWD:-1}"

# Validate username (POSIX-ish)
if ! printf '%s\n' "$KS_USER" | grep -Eq '^[a-z_][a-z0-9_-]*$'; then
  echo "Invalid KS_USER '$KS_USER'"; exit 2
fi

HOME_DIR="/home/${KS_USER}"

# --- Ensure groups exist -------------------------------------------------------
IFS=',' read -r -a _groups <<<"$KS_GROUPS"
for g in "${_groups[@]}"; do
  [ -z "$g" ] && continue
  if ! getent group "$g" >/dev/null 2>&1; then
    # prefer system group, fall back to regular group
    if command -v addgroup >/dev/null 2>&1; then
      addgroup --system "$g" || addgroup "$g" || true
    else
      groupadd -r "$g" || groupadd "$g" || true
    fi
  fi
done

# --- Create or reconcile user --------------------------------------------------
if id -u "$KS_USER" >/dev/null 2>&1; then
  # Ensure shell/home and group memberships
  usermod -s /bin/bash -d "$HOME_DIR" "$KS_USER" || true
  for g in "${_groups[@]}"; do
    [ -z "$g" ] && continue
    id -nG "$KS_USER" | tr ' ' '\n' | grep -qx "$g" || usermod -a -G "$g" "$KS_USER" || true
  done
  [ -d "$HOME_DIR" ] || install -d -o "$KS_USER" -g "$KS_USER" "$HOME_DIR"
else
  # Create user + primary group, home, shell, and memberships
  if command -v adduser >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" --home "$HOME_DIR" --shell /bin/bash "$KS_USER"
  else
    useradd -m -d "$HOME_DIR" -s /bin/bash -U "$KS_USER"
  fi
  for g in "${_groups[@]}"; do
    [ -z "$g" ] && continue
    usermod -a -G "$g" "$KS_USER" || true
  done
fi

chown -R "$KS_USER:$KS_USER" "$HOME_DIR"

# --- Sudo policy (optional) ----------------------------------------------------
if [ "$KS_SUDO_NOPASSWD" = "1" ]; then
  install -d -m 0755 /etc/sudoers.d
  f="/etc/sudoers.d/010-${KS_USER}-nopasswd"
  echo "${KS_USER} ALL=(ALL) NOPASSWD:ALL" >"$f"
  chown 0:0 "$f"
  chmod 0440 "$f"
fi

# --- Persist config for later scripts -----------------------------------------
cat >/etc/ks-user.conf <<EOF
KS_USER=${KS_USER}
HOME_DIR=${HOME_DIR}
KS_GROUPS=${KS_GROUPS}
export KS_USER HOME_DIR KS_GROUPS
EOF

echo "[user] KS_USER=${KS_USER} HOME_DIR=${HOME_DIR} GROUPS=${KS_GROUPS} sudo_nopasswd=${KS_SUDO_NOPASSWD}"
