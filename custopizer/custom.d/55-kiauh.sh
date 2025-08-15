#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh; install_cleanup_trap

# Install KIAUH (clone-only). Do not run it here.
# https://github.com/dw-0/kiauh

# Load target user (your build guarantees this exists)
# shellcheck disable=SC1091
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends git whiptail ca-certificates

# Clone as the target user (no idempotence: will error if ~/kiauh already exists)
runuser -u "${KS_USER}" -- bash -lc '
  set -euo pipefail
  cd "$HOME"
  git clone https://github.com/dw-0/kiauh.git kiauh
'

# Provide a convenient launcher for later interactive use
install -d -m 0755 /usr/local/bin
cat >/usr/local/bin/kiauh <<'WRAP'
#!/usr/bin/env bash
set -e
# Discover KS_USER/HOME_DIR if present
if [ -r /etc/ks-user.conf ]; then . /etc/ks-user.conf; fi
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"
# Update repo (best-effort), then launch KIAUH TUI as the target user
exec runuser -l "${KS_USER}" -c 'cd "${HOME_DIR}/kiauh" && git pull --rebase --autostash || true; exec ./kiauh.sh'
WRAP
chmod 0755 /usr/local/bin/kiauh

# Record revision in manifest (optional)
if [ -d "${HOME_DIR}/kiauh/.git" ]; then
  rev="$(git -C "${HOME_DIR}/kiauh" rev-parse --short HEAD || true)"
  install -d -m 0755 /etc
  printf 'KIAUH\t%s\n' "${rev:-unknown}" >> /etc/ks-manifest.txt
fi
