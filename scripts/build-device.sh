#!/usr/bin/env bash
set -euo pipefail
DEVICE="${DEVICE:-rpi64}"
OUTDIR="${OUTDIR:-out/${DEVICE}-bookworm-arm64}"
LAYERS_FILE="devices/${DEVICE}/layers.yaml"

rm -rf "$OUTDIR"
mkdir -p "$OUTDIR"

sudo apt-get update
sudo apt-get install -y qemu-user-static binfmt-support mmdebstrap bdebstrap podman wget gpg curl
sudo update-binfmts --enable qemu-aarch64 || true

# after deps are installed
KEYRING="/usr/share/keyrings/debian-archive-keyring.gpg"
if [ ! -f "$KEYRING" ]; then
  echo "ERROR: Debian keyring not found at $KEYRING"; exit 2
fi

# --- extract the layer list safely (ignore '---', only bullets under 'layers:') ---
mapfile -t CFGS < <(awk '
  /^[[:space:]]*layers:/ { inlist=1; next }
  inlist && /^[[:space:]]*-/ {
    line=$0
    sub(/^[[:space:]]*-[[:space:]]*/, "", line)   # remove leading "- "
    print line
    next
  }
  inlist && !/^[[:space:]]*-/ { inlist=0 }
' "$LAYERS_FILE")

# Clean each entry: strip inline comments, quotes, whitespace; then validate
VALID=()
for c in "${CFGS[@]}"; do
  c="${c%%#*}"                        # strip inline comment
  c="$(printf "%s" "$c" | tr -d '\r')" # guard against CRLF
  c="$(printf "%s" "$c" | xargs)"      # trim
  c="${c%\"}"; c="${c#\"}"             # remove "quotes"
  c="${c%\'}"; c="${c#\'}"             # remove 'quotes'
  [[ -z "$c" ]] && continue
  [[ ! -f "$c" ]] && { echo "ERROR: layer file not found: $c"; exit 2; }
  VALID+=("$c")
done

if ((${#VALID[@]}==0)); then
  echo "ERROR: no valid layers found in $LAYERS_FILE"
  exit 2
fi

# ... after VALID[] is built ...

echo "==> Building ${DEVICE} with configs:"
printf '   - %s\n' "${VALID[@]}"

OPTS=()
for c in "${VALID[@]}"; do OPTS+=(-c "$c"); done

# Use the host Debian keyring so apt inside mmdebstrap can verify Debian mirrors
KEYRING="/usr/share/keyrings/debian-archive-keyring.gpg"
[ -f "$KEYRING" ] || { echo "ERROR: Missing $KEYRING (install debian-archive-keyring)"; exit 2; }

# Tell bdebstrap to emit a DIRECTORY rootfs at out/.../rootfs
TARGET_DIR="$OUTDIR/rootfs"
mkdir -p "$TARGET_DIR"

podman unshare -- bdebstrap \
  --keyring "$KEYRING" \
  --format directory \
  --target "$TARGET_DIR" \
  "${OPTS[@]}" \
  --name "$OUTDIR"

# Fail-fast if the directory didn’t materialize
[ -f "$TARGET_DIR/etc/os-release" ] || { echo "ERROR: rootfs not created at $TARGET_DIR"; exit 2; }

echo "==> Host post-processing"
bash scripts/host-post.sh "$TARGET_DIR"

echo "==> Done. Rootfs at: $TARGET_DIR"
