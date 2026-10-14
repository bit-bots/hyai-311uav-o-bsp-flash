# HYAI-311UAV-O → JetPack 6.2

Scripts to flash an **HZHY HYAI-311UAV-O** carrier board with an **NVIDIA Jetson Orin NX** module
to **JetPack 6.2 (L4T 36.4.3)**.

The firmware is HZHY's own JetPack 6.2 build for this carrier board. It is not a stock NVIDIA
image, so board peripherals (fan header, CAN, GPIO mapping) work as HZHY adapted them.

## Manufacturer

The HYAI-311UAV-O carrier board and its JetPack firmware are made by **HZHY**: Beijing HZHY
Technology Co., Ltd. (北京合众恒跃科技有限公司). They provided the firmware hosted on our
[mirror](https://data.bit-bots.de/jetson/jetpack/hyai-311uav-o/). For
boards, other carrier designs, or support, contact them directly:

| | |
|---|---|
| Website | [www.hzhytech.com](http://www.hzhytech.com/) |
| Sales | [sam@hzhytech.com](mailto:sam@hzhytech.com) |
| Phone | +86 10 6212 9511 |
| Address | 北京市海淀区安宁庄后街南1号A区一层1020号, 102208 Beijing, China |

## Dependencies

- **Linux host with native Docker.** Docker Desktop or a VM won't work, because the flash needs
  real USB passthrough and host networking.
- About **35 GB free disk**: 6.4 GB archive + ~28 GB extracted BSP.
- `curl`, `sha256sum`, root access via `sudo`.
- A USB-C cable from the host to the board's flash port **J7**.

## Usage

```bash
cd scripts
./fetch-bsp.sh    # download the JP6.2 archive (6.4 GB) into software-design/, resumable, sha256-checked
sudo ./setup.sh   # once: extract the archive to scripts/Linux_for_Tegra/, build the jp6-flash Docker image
sudo ./flash.sh   # flash the board (interactive)
```

`flash.sh` walks you through putting the board into **recovery mode**:

- **Board running:** run `sudo reboot --force forced-recovery` on the Jetson itself.
- **Board off or unresponsive:** hold **SW1** (REC), apply power, keep holding 3–4 s, release.

It then waits for the board to appear on USB, and offers to create a default `nvidia`/`nvidia`
login so you can skip first-boot setup. Then it flashes QSPI and the NVMe. Don't touch the cable
or power until it finishes.

Afterwards, power-cycle the board. It boots from NVMe into JetPack 6.2. If it doesn't: press
**ESC** at boot → Boot Maintenance Manager → Boot Options → Change Boot Order → move NVMe to the
top → **F10**, **Y**.

Then run through the post-flash checks in [`scripts/CHECKLIST.md`](scripts/CHECKLIST.md) §3–4.

## ⚠️ Never `apt upgrade` the flashed board

HZHY's image ships a custom kernel and board adaptation layer that an `apt upgrade` overwrites.
This includes the unattended upgrades Ubuntu has enabled by default. `sudo apt install
nvidia-jetpack` to add missing NVIDIA components is fine.

## Troubleshooting

[`scripts/CHECKLIST.md`](scripts/CHECKLIST.md) §5 lists every failure hit while building this
kit, with its error message and fix. Check it first. To test image generation without a board,
see "Validating without touching the board" at the end of that file.

## Layout

| Path | What |
|---|---|
| `scripts/fetch-bsp.sh` | Downloads and verifies the firmware archive. `./fetch-bsp.sh jp5` fetches the older JetPack 5.1.4 build, which is untested and not used by `setup.sh` (TODO). |
| `scripts/setup.sh` | Extracts the archive and builds the Docker image. |
| `scripts/flash.sh` | Recovery-mode check and flash. |
| `scripts/Dockerfile` | Ubuntu 22.04 with NVIDIA's flash prerequisites. |
| `scripts/CHECKLIST.md` | Step-by-step flash, post-flash checks, known problems. |
| `CHECKSUMS.txt` | SHA-256 of the known-good firmware archives. |
