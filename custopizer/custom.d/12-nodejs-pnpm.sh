#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh; install_cleanup_trap

# Node.js + pnpm (early install)
# - Default to Node.js 22.x (override with NODE_MAJOR)
# - Install pnpm globally via npm (override PNPM_VERSION, default "latest")
: "${NODE_MAJOR:=22}"
: "${PNPM_VERSION:=latest}"

export DEBIAN_FRONTEND=noninteractive

# Minimal prerequisites
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg

# Add NodeSource APT repo (key in keyring; Signed-By on the source)
install -d -m 0755 /usr/share/keyrings /etc/apt/sources.list.d
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg

cat >/etc/apt/sources.list.d/nodesource.list <<EOF
deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main
EOF

apt-get update
apt-get install -y --no-install-recommends nodejs

# (Optional) toolchain for native addons; uncomment if your node deps need it
# apt-get install -y --no-install-recommends build-essential python3 make g++

# Install pnpm globally
npm --version >/dev/null
npm install -g "pnpm@${PNPM_VERSION}"

# Record versions in manifest
install -d -m 0755 /etc
{
  printf 'Node.js\t%s\n' "$(node -v || true)"
  printf 'npm\t%s\n' "$(npm -v || true)"
  printf 'pnpm\t%s\n' "$(pnpm -v || true)"
} >> /etc/ks-manifest.txt

echo_green "[nodejs] $(node -v)  [npm] $(npm -v)  [pnpm] $(pnpm -v)"
