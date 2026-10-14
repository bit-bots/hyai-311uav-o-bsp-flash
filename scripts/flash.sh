#!/usr/bin/env bash
# Flash HYAI-311UAV-O (Orin NX) to JetPack 6.2 via the dockerized BSP tools.
# Run: sudo ./setup.sh   (once)
#      sudo ./flash.sh   (each flash)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACT_DIR="$SCRIPT_DIR/Linux_for_Tegra"
IMAGE_TAG="jp6-flash:latest"
BOARD_TARGET="jetson-orin-nano-devkit-super-nvme"   # matches p3768-0000-p3767-0000-super-maxn-nvme.conf (Orin NX + NVMe, Super mode)
# NVIDIA USB VID:PID seen in recovery mode, per module variant
RECOVERY_IDS='0955:7323|0955:7423|0955:7523|0955:7623'  # Orin NX16G|NX8G|Nano8G|Nano4G

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo $0" >&2
    exit 1
fi

if [[ ! -f "$EXTRACT_DIR/nv_tegra/bsp_version" ]]; then
    echo "BSP not extracted. Run ./setup.sh first." >&2
    exit 1
fi

if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
    echo "Docker image $IMAGE_TAG not built. Run ./setup.sh first." >&2
    exit 1
fi

# nfsd is a KERNEL service, so the container cannot start it itself: it has no
# modprobe and no /lib/modules, and the flash tool's `service nfs-kernel-server
# restart` then dies with "no support in current kernel" -> "NFS server is not
# running" (exit 114). Load it here on the host instead; the container's
# rpc.nfsd then drives the host kernel's nfsd via --privileged.
# ponytail: modprobe per run instead of /etc/modules-load.d — flash.sh is the
# only thing here that needs nfsd, no reason to load it at every host boot.
if ! lsmod | grep -q '^nfsd'; then
    echo "Loading host nfsd kernel module (needed by the flash tool's NFS session)..."
    modprobe nfsd || {
        echo "ERROR: could not load the nfsd kernel module on this host." >&2
        echo "The flash tool serves the rootfs to the board over NFS and cannot work without it." >&2
        exit 1
    }
fi

echo "=================================================================="
echo " HYAI-311UAV-O -> JetPack 6.2 (L4T 36.4.3) flash"
echo "=================================================================="
echo
echo "1. Connect the flashing Type-C cable to J7 on the board."
echo
echo "2. Enter recovery mode — try software first, fall back to the button:"
echo
echo "   Software (board must be currently booted + reachable via SSH/console):"
echo "     sudo reboot --force forced-recovery"
echo "   Run that ON THE JETSON ITSELF, not on this host. It only works if"
echo "   the board is alive and running — if it's unresponsive/bricked,"
echo "   skip straight to the button method below."
echo
echo "   Button fallback (always works, use if the software trigger didn't):"
echo "     Power off the board, hold SW1 (REC button), apply power, keep"
echo "     holding 3-4 sec, release."
echo
read -rp "Press Enter once the board is powered on in recovery mode... "

echo
echo "Waiting for the board to enumerate in recovery mode (Ctrl-C to abort)..."
found=""
for i in $(seq 1 30); do
    if lsusb | grep -Eq "$RECOVERY_IDS"; then
        found="$(lsusb | grep -E "$RECOVERY_IDS")"
        break
    fi
    sleep 2
done

if [[ -z "$found" ]]; then
    echo "ERROR: no NVIDIA recovery-mode device seen after 60s." >&2
    echo "Power off, retry holding SW1, and re-run this script." >&2
    exit 1
fi

echo "Found: $found"
echo

read -rp "Bake in a default nvidia/nvidia login (skips first-boot OOBE)? [y/N] " make_user
if [[ "${make_user,,}" == "y" ]]; then
    docker run --rm --privileged \
        -v "$EXTRACT_DIR:/work" -w /work \
        "$IMAGE_TAG" \
        ./tools/l4t_create_default_user.sh -u nvidia -p nvidia -n nvidia-desktop -a --accept-license
fi

echo
echo "Flashing now — do not disconnect the cable or power off the board."
echo

# -v /dev:/dev (not just /dev/bus/usb): image generation attaches several loop devices at once
# (flash.sh:1537 `losetup --show -f esp.img`). Docker gives the container its own /dev tmpfs
# snapshot, so when the kernel auto-creates /dev/loop1 for the second concurrent attach the node
# lands in the HOST devtmpfs and is invisible inside the container -> losetup fails with
# "esp.img: failed to set up loop device: No such file or directory". Sharing host /dev live makes
# newly created loop nodes appear immediately. Covers the USB passthrough too.
docker run --rm --privileged --net=host \
    -v /dev:/dev \
    -v "$EXTRACT_DIR:/work" -w /work \
    "$IMAGE_TAG" \
    ./tools/kernel_flash/l4t_initrd_flash.sh \
      --external-device nvme0n1p1 \
      -c tools/kernel_flash/flash_l4t_t234_nvme.xml \
      -p "-c bootloader/generic/cfg/flash_t234_qspi.xml" \
      --showlogs --network usb0 \
      "$BOARD_TARGET" internal

echo
echo "=================================================================="
echo " Flash finished. Power-cycle the board (remove REC hold)."
echo " It should boot straight from NVMe into JetPack 6.2."
echo " If it doesn't: ESC at boot -> Boot Maintenance Manager -> Boot"
echo " Options -> Change Boot Order -> move NVMe entry to top -> F10, Y."
echo
echo " Then run the post-flash smoke tests from CHECKLIST.md."
echo "=================================================================="
