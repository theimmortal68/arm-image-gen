#!/usr/bin/env bash
# build-bdebstrap.sh
# Usage:
#   scripts/build-bdebstrap.sh <device> <devices/<device>/layers.yaml> [outdir]
#
# Reads the layers YAML (expects a `layers:` list) and runs bdebstrap with each file via `-c <file>`.
# Produces a rootfs directory at the OUTDIR you provide (default: out/<device>-bookworm-arm64).

set -euo pipefail

DEVICE="${1:?device name (e.g., rpi64)}"
LAYERS_FILE="${2:?path to devices/<device>/layers.yaml}"
OUTDIR="${3:-out/${DEVICE}-bookworm-arm64}"

if ! command -v bdebstrap >/dev/null 2>&1; then
  echo "ERROR: bdebstrap not found in PATH" >&2
  exit 1
fi

if [ ! -s "$LAYERS_FILE" ]; then
  echo "ERROR: layers file not found or empty: $LAYERS_FILE" >&2
  exit 1
fi

# Extract YAML list entries (lines beginning with "- ") as config paths.
# This intentionally keeps things simple; it assumes your layers.yaml only lists the files you want.
readarray -t CONFIGS < <(
  awk '
    /^[[:space:]]*-[[:space:]]/ {
      sub(/^- /, "", $0);
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0);
      print $0
    }
  ' "$LAYERS_FILE" | sed '/^#/d;/^$/d'
)

if [ "${#CONFIGS[@]}" -eq 0 ]; then
  echo "ERROR: No config entries found in $LAYERS_FILE" >&2
  exit 1
fi

echo "==> Building ${DEVICE} with configs:"
for c in "${CONFIGS[@]}"; do
  echo "   - ${c}"
done

# Clean existing outdir explicitly (avoids bdebstrap refusing to reuse)
if [ -e "$OUTDIR" ]; then
  echo "Removing existing $OUTDIR"
  rm -rf "$OUTDIR"
fi
mkdir -p "$(dirname "$OUTDIR")"

# Prefer running under 'podman unshare' if available (helps with subuid/subgid mount permissions)
RUNNER_ARR=()
if command -v podman >/dev/null 2>&1; then
  RUNNER_ARR=(podman unshare --)
fi

# Build the bdebstrap command with -c before EVERY layer file
CMD=(bdebstrap --force --name "$OUTDIR")
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
