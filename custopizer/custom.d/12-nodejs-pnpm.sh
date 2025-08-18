#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh
install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

export DEBIAN_FRONTEND=noninteractive

section "Install Node.js 22.x via NodeSource setup script"

# Clean up any previous manual NodeSource entries (from earlier attempts)
rm -f /etc/apt/sources.list.d/nodesource.list /etc/apt/keyrings/nodesource.gpg || true

apt_update_once || true
apt_install ca-certificates curl gnupg

# Official NodeSource installer auto-detects distro/codename and configures apt + keys
# NOTE: we're root in chroot, so no sudo.
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -

# Install Node.js (provides /usr/bin/node and /usr/bin/npm)
apt-get -y --no-install-recommends install nodejs

# Quiet npm in CI logs (reduce harmless noise)
npm config set fund false
npm config set audit false
npm config set update-notifier false
npm config set loglevel warn || true

# Enable Corepack so pnpm/yarn are managed deterministically
corepack enable || true
# Pin pnpm if you want: export PNPM_VERSION=9.12.3 before running this step
if [ -n "${PNPM_VERSION:-}" ]; then
  corepack prepare "pnpm@${PNPM_VERSION}" --activate || true
else
  corepack prepare pnpm@latest --activate || true
fi

# Traceability
node -v
npm -v
pnpm -v || true
