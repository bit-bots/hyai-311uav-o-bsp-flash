#!/usr/bin/env bash
# One-time setup: extract the JP6.2 BSP archive + build the docker image.
# Run this once after rsyncing hyai-311uav-o-jp6/ to the Linux laptop.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ARCHIVE="$REPO_ROOT/software-design/flash-311UAV-O-V2.0_ONX_Jp6.2_SC_v1.0.0_20251204.tar.gz"
EXTRACT_DIR="$SCRIPT_DIR/Linux_for_Tegra"
IMAGE_TAG="jp6-flash:latest"

if [[ $EUID -ne 0 ]]; then
    echo "Run as root (sudo $0) — extraction needs to preserve device-node/permission bits in the rootfs." >&2
    exit 1
fi

if [[ ! -f "$ARCHIVE" ]]; then
    echo "Archive not found: $ARCHIVE — run ./fetch-bsp.sh first." >&2
    exit 1
fi

if [[ -f "$EXTRACT_DIR/nv_tegra/bsp_version" ]]; then
    echo "[1/2] Already extracted at $EXTRACT_DIR — skipping."
else
    echo "[1/2] Extracting BSP archive (~11GB, a few minutes)..."
    tmp="$SCRIPT_DIR/.extract_tmp"
    rm -rf "$tmp"
    mkdir -p "$tmp"
    tar xzf "$ARCHIVE" -C "$tmp"
    # archive contains one top-level versioned dir; flatten it to Linux_for_Tegra/
    inner="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d)"
    mv "$inner/Linux_for_Tegra" "$EXTRACT_DIR"
    rm -rf "$tmp"
    echo "Extracted to $EXTRACT_DIR"
fi

echo "[2/2] Building docker image $IMAGE_TAG ..."
docker build -t "$IMAGE_TAG" "$SCRIPT_DIR"

echo
echo "Setup done. Next: sudo ./flash.sh"
