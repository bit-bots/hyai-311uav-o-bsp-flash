# AGENTS.md and CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) and other agents when working with code in this repository.

## What this repo is

Not a software project — a docker-based toolkit (`scripts/`) to flash the **HZHY HYAI-311UAV-O**
carrier board (NVIDIA Jetson Orin NX 8GB/16GB module) to **JetPack 6.2 / L4T 36.4.3**. No vendor
material is in the repo: the firmware archives and HZHY's PDF manuals live on the bit-bots mirror
(https://data.bit-bots.de/jetson/jetpack/hyai-311uav-o/ — `jp6/`, `jp5/`, `user-manuals/`), and
`fetch-bsp.sh` pulls the firmware from there. English filenames are Claude-authored renames of the
original vendor drop, which used Chinese directory/file names (untouched original at
`~/HYAI-311UAV_O_v12` on the flashing laptop). User-facing docs: `README.md`.

## Commands

Flashing only runs on Linux with native Docker (not Docker Desktop/VM — needs real USB passthrough).

```bash
cd scripts
./fetch-bsp.sh     # no root: downloads the JP6.2 archive from the bit-bots mirror
                   # (https://data.bit-bots.de/jetson/jetpack/hyai-311uav-o/) into
                   # software-design/, resumable, sha256-checked against CHECKSUMS.txt.
                   # `./fetch-bsp.sh jp5` for the untested JP5.1.4 archive.
sudo ./setup.sh    # one-time: extracts software-design/flash-*Jp6.2*.tar.gz to
                   # scripts/Linux_for_Tegra/, builds the jp6-flash docker image
sudo ./flash.sh    # interactive flash: prompts for recovery-mode entry (software
                   # `reboot --force forced-recovery` on the target first, SW1 button
                   # fallback), polls `lsusb` for the device, then runs the flash
```

`setup.sh` and `flash.sh` must run as root (rootfs extraction needs to preserve device-node
permissions; the flash itself needs raw USB + host networking). No separate lint/test/build step —
`docker build` inside `setup.sh` is the only build, and there's no test suite (this is a hardware
flashing operation, verified post-hoc against real hardware — see `scripts/CHECKLIST.md`).

`software-design/` and `scripts/Linux_for_Tegra/` are gitignored download/extract targets.

To flash the older JetPack 5.1.4 package instead, `setup.sh`'s `ARCHIVE`/`EXTRACT_DIR` would need
repointing — they're hardcoded to the JP6.2 archive only.

## Architecture

- `scripts/Dockerfile` — Ubuntu 22.04 + the exact package list from the vendored
  `tools/l4t_flash_prerequisites.sh` (inside the JP6.2 archive) plus `sudo`/`usbutils`/
  `openssh-client`, and `ENV USER=root`. This is the flashing environment; nothing here is built
  from source, it's all NVIDIA-provided binary tooling.
- `scripts/fetch-bsp.sh` — `curl -C -` into `software-design/`, then sha256 check; deletes on mismatch.
- `scripts/setup.sh` — idempotent: extracts the tar.gz (skips if `Linux_for_Tegra/nv_tegra/bsp_version`
  already exists), then `docker build`s the image.
- `scripts/flash.sh` — the actual flash procedure. Key details baked in:
  - `BOARD_TARGET=jetson-orin-nano-devkit-super-nvme` — matches
    `p3768-0000-p3767-0000-super-maxn-nvme.conf` in the BSP (Orin NX, NVMe root, Super/MAXN power mode).
  - Recovery-mode detection matches USB IDs `0955:7323|7423|7523|7623` (Orin NX 16GB/8GB, Orin Nano 8GB/4GB).
  - Loads the host `nfsd` module (the container can't).
  - Docker run flags are load-bearing, not arbitrary: `--privileged` (raw USB + loop devices),
    `-v /dev:/dev` (USB device + loop nodes created mid-run), `--net=host` (the flash tool runs
    an NFS+SSH session to the target over a `usb0` interface it creates — bridged/NAT docker
    networking breaks this). Every one of these was a failed flash; see `scripts/CHECKLIST.md` §5.
  - Flash command is `tools/kernel_flash/l4t_initrd_flash.sh --external-device nvme0n1p1 -c
    tools/kernel_flash/flash_l4t_t234_nvme.xml -p "-c bootloader/generic/cfg/flash_t234_qspi.xml"`.
  - REC button on this specific carrier board is **SW1** (varies by HZHY board model — see
    `user-manuals/HZHY-NVIDIA-Series-Quick-Flash-Tutorial-20250711.pdf` on the mirror for the per-board table);
    flash port is the Type-C connector at **J7**.
- The firmware archives are HZHY's own pre-adapted L4T BSP + rootfs builds for this exact carrier
  board, not stock NVIDIA images — don't substitute a stock NVIDIA JetPack image and expect
  board-specific peripherals (fan header, CAN, GPIO mapping) to work.
- `user-manuals/` on the mirror (not in the repo) — HZHY's board manual, interface test instructions
  (written against JetPack 4/5; GPIO and camera test scripts there are **not** guaranteed compatible
  with JetPack 6's libgpiod/Argus stack — see `scripts/CHECKLIST.md`), flash tutorial, boot-order setup.
- `README.md` § Manufacturer — HZHY's name and contact. Promoting HZHY was a condition of their
  permission to mirror the firmware, so keep that section prominent and don't trim it.

## Rules carried over from the vendor docs

- **Never `apt upgrade`** a flashed image — breaks HZHY's board adaptation layer.
  `apt install nvidia-jetpack` for missing official components is fine.
- Extract the BSP archive as root via CLI `tar`, never a GUI unzip tool (vendor's own instruction,
  `setup.sh` already does this correctly).
