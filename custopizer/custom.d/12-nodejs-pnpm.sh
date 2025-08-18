#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh
install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

export DEBIAN_FRONTEND=noninteractive

section "Install Node.js 22.x and pnpm (via Corepack)"

# Detect distro codename for NodeSource (works for Debian/Raspberry Pi OS & Ubuntu/Armbian)
. /etc/os-release
CODENAME="${VERSION_CODENAME:-bookworm}"

# Prereqs
apt-get -o Acquire::Retries=3 update
apt-get -y --no-install-recommends install ca-certificates curl gnupg

# NodeSource repo/key (no nvm; ensures /usr/bin/node and /usr/bin/npm are present)
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg

echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x ${CODENAME} main" \
  > /etc/apt/sources.list.d/nodesource.list

apt-get -o Acquire::Retries=3 update
apt-get -y --no-install-recommends install nodejs

# Quiet npm in CI logs (no audit/fund/notify; warn-level logs)
npm config set fund false
npm config set audit false
npm config set update-notifier false
npm config set loglevel warn

# Enable Corepack and (optionally) pin pnpm.
# If you want a specific pnpm, export PNPM_VERSION before running (e.g., PNPM_VERSION=9.12.3)
corepack enable || true
if [ -n "${PNPM_VERSION:-}" ]; then
  corepack prepare "pnpm@${PNPM_VERSION}" --activate
else
  # Use whatever Corepack ships with Node 22; you can pin later if desired.
  corepack prepare pnpm@latest --activate || true
fi

# Sanity
node -v
npm -v
pnpm -v || true  # present if corepack activated it

echo "[node] Installed Node.js $(node -v) and npm $(npm -v)"
