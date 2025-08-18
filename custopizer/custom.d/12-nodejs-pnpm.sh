#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh
install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

export DEBIAN_FRONTEND=noninteractive

section "Install NPM and PNPM"

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
