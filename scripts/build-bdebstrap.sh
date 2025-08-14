#!/usr/bin/env bash
# build-bdebstrap.sh
# Usage:
#   scripts/build-bdebstrap.sh <device> <devices/<device>/layers.yaml> [outdir]
#
# Reads the layers YAML (expects a `layers:` list) and runs bdebstrap with each file via `-c <file>`.
# Produces a rootfs directory at OUTDIR/rootfs (default OUTDIR: out/<device>-bookworm-arm64).

set -euo pipefail

DEVICE="${1:?device name (e.g., rpi64)}"
LAYERS_FILE="${2:?path to devices/<device>/layers.yaml}"
OUTDIR="${3:-out/${DEVICE}-bookworm-arm64}"
TARGET_DIR="${OUTDIR}/rootfs"

if ! command -v bdebstrap >/dev/null 2>&1; then
  echo "ERROR: bdebstrap not found in PATH" >&2
  exit 1
fi

if [ ! -s "$LAYERS_FILE" ]; then
  echo "ERROR: layers file not found or empty: $LAYERS_FILE" >&2
  exit 1
fi

# Normalize CRLF and extract YAML list entries (strip leading "- ", drop comments/blank)
mapfile -t CONFIGS < <(
  sed 's/\r$//' "$LAYERS_FILE" \
  | sed -E -n 's/^[[:space:]]*-[[:space:]]+([^#]+).*$/\1/p' \
  | sed -E 's/[[:space:]]+$//'
)

if [ "${#CONFIGS[@]}" -eq 0 ]; then
  echo "ERROR: No config entries found in $LAYERS_FILE" >&2
  exit 1
fi

# Verify each config exists before running
for cfg in "${CONFIGS[@]}"; do
  if [ ! -f "$cfg" ]; then
    echo "ERROR: layer file not found: $cfg" >&2
    exit 1
  fi
done

echo "==> Building ${DEVICE} with configs:"
for c in "${CONFIGS[@]}"; do
  echo "   - ${c}"
done

# Clean/recreate output dirs
if [ -e "$OUTDIR" ]; then
  echo "Removing existing $OUTDIR"
  rm -rf "$OUTDIR"
fi
mkdir -p "$TARGET_DIR"

# Prefer running under 'podman unshare' if available (can be disabled via NO_UNSHARE=1)
RUNNER_ARR=()
if [[ -z "${NO_UNSHARE:-}" ]] && command -v podman >/dev/null 2>&1; then
  RUNNER_ARR=(podman unshare --)
fi

# Build the bdebstrap command with:
# - explicit --target for directory format
# - -c before EVERY layer file
CMD=(bdebstrap --force --name "$OUTDIR" --target "$TARGET_DIR")
for cfg in "${CONFIGS[@]}"; do
  CMD+=(-c "$cfg")
done

# Show the exact command about to run (with proper quoting)
printf 'Running:'; printf ' %q' "${RUNNER_ARR[@]}" "${CMD[@]}"; echo

# Execute
if [ "${#RUNNER_ARR[@]}" -gt 0 ]; then
  "${RUNNER_ARR[@]}" "${CMD[@]}"
else
  "${CMD[@]}"
fi

echo "==> bdebstrap completed: $OUTDIR"
