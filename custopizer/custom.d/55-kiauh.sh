#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

source /common.sh; install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

section "Clone KIAUH (do not run installer in chroot)"

# Target user/home
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

apt_install git whiptail ca-certificates

# Clone as the target user (no idempotence per your policy)
as_user "${KS_USER}" 'cd "$HOME" && git clone https://github.com/dw-0/kiauh.git kiauh'

# Provide a convenient launcher wrapper
install -d -m 0755 /usr/local/bin
cat >/usr/local/bin/kiauh <<'WRAP'
#!/usr/bin/env bash
set -e
if [ -r /etc/ks-user.conf ]; then . /etc/ks-user.conf; fi
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"
exec runuser -l "${KS_USER}" -c 'cd "${HOME_DIR}/kiauh" && git pull --rebase --autostash || true; exec ./kiauh.sh'
WRAP
chmod 0755 /usr/local/bin/kiauh

# Record revision in manifest (optional)
if [ -d "${HOME_DIR}/kiauh/.git" ]; then
  rev="$(git -C "${HOME_DIR}/kiauh" rev-parse --short HEAD || true)"
  install -d -m 0755 /etc
  printf 'KIAUH\t%s\n' "${rev:-unknown}" >> /etc/ks-manifest.txt
fi

echo_green "[KIAUH] cloned and wrapper installed; run 'kiauh' on the device to launch the TUI"
apt_clean_all
