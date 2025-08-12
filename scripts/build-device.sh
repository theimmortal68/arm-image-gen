
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
podman unshare -- bdebstrap -l "$LAYERS" --name "$OUTDIR"

echo "==> Host post-processing"
bash scripts/host-post.sh "$OUTDIR/rootfs"

echo "==> Done. Rootfs at: $OUTDIR/rootfs"
