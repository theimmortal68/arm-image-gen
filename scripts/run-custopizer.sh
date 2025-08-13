#!/usr/bin/env bash
# Usage: run-custopizer.sh <input_img> <out_img> [enlargeroot_mb]
# Runs custopizer container with DNS override and your custom.d scripts.
set -euo pipefail

IN_IMG="${1:?input image path}"
OUT_IMG="${2:?output image path}"
ENLARGEROOT="${3:-8000}"

if [ ! -s "$IN_IMG" ]; then
  echo "Input image not found: $IN_IMG" >&2
  exit 1
fi

docker run --rm \
  --dns 8.8.8.8 --dns 8.8.4.4 \
  -v "${PWD}:/CustoPiZer/workspace" \
  ghcr.io/octoprint/custopizer:latest \
    --image "$IN_IMG" \
    --customizations ./custopizer/custom.d \
    --enlargeroot "$ENLARGEROOT" \
    --out "$OUT_IMG"
