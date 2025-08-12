
#!/usr/bin/env bash
set -euo pipefail
DEVICE="${DEVICE:-rpi64}"
OUTDIR="${OUTDIR:-out/${DEVICE}-bookworm-arm64}"
LAYERS="devices/${DEVICE}/layers.yaml"

rm -rf "$OUTDIR"
mkdir -p "$OUTDIR"

sudo apt-get update
sudo apt-get install -y qemu-user-static binfmt-support mmdebstrap podman wget gpg curl
sudo update-binfmts --enable qemu-aarch64 || true

echo "==> Building ${DEVICE} with layers ${LAYERS}"
LAYERS_FILE="devices/${DEVICE}/layers.yaml"

# Extract list items from layers.yaml (lines that start with "- ")
mapfile -t CFGS < <(sed -n 's/^[[:space:]]*-[[:space:]]*\(.*\)$/\1/p' "$LAYERS_FILE")
if [ "${#CFGS[@]}" -eq 0 ]; then
  echo "No layers found in $LAYERS_FILE"; exit 2
fi

OPTS=()
for c in "${CFGS[@]}"; do
  OPTS+=(-c "$c")
done

echo "==> Building ${DEVICE} with configs:"
printf '   - %s\n' "${CFGS[@]}"

podman unshare -- bdebstrap "${OPTS[@]}" --name "$OUTDIR"

echo "==> Host post-processing"
bash scripts/host-post.sh "$OUTDIR/rootfs"

echo "==> Done. Rootfs at: $OUTDIR/rootfs"
