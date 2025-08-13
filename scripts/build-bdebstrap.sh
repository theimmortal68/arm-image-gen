#!/usr/bin/env bash
# Usage: build-bdebstrap.sh <device> <layers.yaml> [outdir]
# Reads the layers YAML (expects `layers:` list) and runs bdebstrap with each -c config.
set -euo pipefail

DEVICE="${1:?device name (e.g., rpi64)}"
LAYERS_FILE="${2:?path to devices/<device>/layers.yaml}"
OUTDIR="${3:-out/${DEVICE}-bookworm-arm64}"

if ! command -v bdebstrap >/dev/null 2>&1; then
  echo "bdebstrap not found in PATH" >&2
  exit 1
fi

# Parse YAML lines beginning with "- " as config paths
readarray -t CONFIGS < <(awk '/^[[:space:]]*-[[:space:]]/{sub(/^- /,""); print}' "$LAYERS_FILE" | sed 's/^[[:space:]]*//')

if [ "${#CONFIGS[@]}" -eq 0 ]; then
  echo "No config entries found in $LAYERS_FILE" >&2
  exit 1
fi

echo "==> Building ${DEVICE} with configs:"
for c in "${CONFIGS[@]}"; do echo "   - ${c}"; done

# Clean existing outdir (bdebstrap has --force, but we make it explicit)
if [ -e "$OUTDIR" ]; then
  echo "Removing existing $OUTDIR"
  rm -rf "$OUTDIR"
fi
mkdir -p "$(dirname "$OUTDIR")"

# Prefer running under podman unshare if available (helps with mount perms)
RUNNER=""
if command -v podman >/dev/null 2>&1; then
  RUNNER="podman unshare -- "
fi

CMD=(bdebstrap --force --name "$OUTDIR")
for cfg in "${CONFIGS[@]}"; do
  CMD+=(-c "$cfg")
done

echo "Running: ${RUNNER}${CMD[*]}"
eval "${RUNNER}${CMD[*]}"
echo "==> bdebstrap done: $OUTDIR"
