# Jetson JetPack 6.2 flash environment for HYAI-311UAV-O (Orin NX)
# Build: sudo ./setup.sh
# Run:   sudo ./flash.sh
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Exact package list from the vendored tools/l4t_flash_prerequisites.sh
# (inside the Jp6.2 archive) + sudo, since l4t_initrd_flash.sh shells out
# to `sudo` internally even when already running as root.
RUN apt-get update && apt-get install -y --no-install-recommends \
    abootimg binfmt-support binutils cpio cpp \
    device-tree-compiler dosfstools \
    iproute2 iputils-ping lbzip2 libxml2-utils \
    netcat-openbsd nfs-kernel-server openssl \
    python3-yaml qemu-user-static rsync sshpass \
    udev uuid-runtime whois xmlstarlet zstd \
    lz4 sudo usbutils ca-certificates \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*
# openssh-client is NOT in the vendored prerequisites list, but the flash path needs it twice:
#   - ota_make_recovery_img_dtb.sh:112-115 runs `ssh-keygen` to make the recovery initrd's host
#     keys. It's guarded by a bare `check_error`, so a missing binary surfaces only as
#     "command is failed" / "Error: failed to generate images" with no mention of ssh.
#   - l4t_initrd_flash_internal.sh:350,359 ssh into the booted target over IPv6 link-local.
# parted/partprobe/xxd also appear in the flash scripts but only in l4t_flash_from_kernel.sh,
# which runs ON THE TARGET inside the initrd; they're copied in from rootfs by
# recovery_copy_binlist.txt, so they are deliberately not installed here.

# Several BSP scripts gate on the $USER env var rather than the real uid, e.g.
#   tools/kernel_flash/l4t_create_images_for_kernel_flash.sh:562
#   tools/kernel_flash/l4t_flash_from_kernel.sh:1372
#   flash.sh:2192
#       if [ "${USER}" != "root" ]; then echo "... requires root privilege"; exit 207
# Docker does not set $USER, so those abort with exit 207 even though the
# container already runs as uid 0. Setting it here fixes all of them at once —
# the alternative is patching each vendor script, which breaks on every BSP
# update. Placed after the apt layer so rebuilds stay cached.
ENV USER=root

WORKDIR /work
