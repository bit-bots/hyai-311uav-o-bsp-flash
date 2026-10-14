# JetPack 6.2 upgrade checklist — HYAI-311UAV-O (Orin NX)

## 0. Host
- [ ] `docker --version` works (install `docker` package + `sudo systemctl enable --now docker` if not)
- [ ] Confirm you're on native Linux Docker, not a VM/Desktop — USB passthrough needs the real kernel.

## 1. One-time setup
- [ ] `cd scripts`
- [ ] `./fetch-bsp.sh` — downloads the JP6.2 archive (6.4GB) from the mirror, verifies sha256.
- [ ] `sudo ./setup.sh` — extracts the JP6.2 BSP and builds the `jp6-flash` docker image.

## 2. Flash
- [ ] Cable: flashing Type-C into **J7** on the board.
- [ ] Try software recovery trigger first (only if board currently boots):
      on the Jetson itself — `sudo reboot --force forced-recovery`
- [ ] If that doesn't work / board is unresponsive: hold **SW1**, apply power, hold 3-4s, release.
- [ ] `sudo ./flash.sh` — waits for recovery-mode USB enumeration, optionally bakes in
      `nvidia`/`nvidia` default login, then flashes.
- [ ] Watch for "Flashing completed" in the log. Don't touch the cable/board meanwhile.

## 3. First boot
- [ ] Power-cycle (release SW1 if still held).
- [ ] Board should boot straight from NVMe into JetPack 6.2.
- [ ] If it doesn't boot to NVMe: **ESC** at boot → Boot Maintenance Manager → Boot Options →
      Change Boot Order → move NVMe entry to top → **F10**, **Y** to save.
- [ ] Login: `nvidia`/`nvidia` if you baked in the default user, else complete OOBE.
- [ ] `cat /etc/nv_tegra_release` — confirm it reports R36 (L4T 36.4.3 / JetPack 6.2).

## 4. Post-flash smoke test
Rules from HZHY docs: **never `apt upgrade`** the image (breaks their adaptation).
`sudo apt update && sudo apt install nvidia-jetpack` is fine if components are missing.

- [ ] USB3: plug a U-disk/camera into the two USB3.0 ports → `dmesg | grep -i peed` shows "SuperSpeed"
- [ ] Ethernet: `ip a`, static IP if needed, `ping <gateway>`
- [ ] HDMI: display shows output
- [ ] Debug UART (J6): connect at 115200 (JP6 default), confirm console login
- [ ] NVMe: already implied by successful boot, but confirm `lsblk` shows the SSD healthy
- [ ] CAN (J2): test with CANalyst-II + on-board CAN loopback tool if present on the image
- [ ] RS232/TTL UART (J11/J13, 9600 baud): loopback/echo test if present on the image
- [ ] Camera/CSI: **JetPack 6 changed the camera stack (Argus/gstreamer)** — old JP4/5
      `cameraTest.sh` scripts from the test doc are not guaranteed to work. Verify manually with
      `gst-launch-1.0 nvarguscamerasrc ! ...` or `v4l2-ctl --list-devices`.
- [ ] GPIO: **JetPack 6 uses libgpiod, not legacy sysfs.** Old `gpio_311UAV` script (sysfs-based)
      will likely need porting — check with `gpiodetect` / `gpioinfo` first.
- [ ] Fan (J12, PWM+tach): confirm fan spins under load, check `/sys/class/hwmon` for tach/PWM nodes.

## 5. Known gotchas
- Docker on Docker Desktop (Mac/Windows) won't give reliable USB passthrough — this whole kit
  assumes native Linux Docker (Arch, confirmed working pattern).
- `l4t_initrd_flash.sh` needs `--net=host` — it runs an NFS/SSH session to the target over a
  `usb0` interface during flashing. Bridged/NAT docker networking breaks this.
- Only ONE device in recovery mode on the USB bus at a time.
- If `nfs-kernel-server`/`rpcbind` fail to start inside the container, something on the host is
  likely already bound to those ports — `sudo systemctl stop nfs-kernel-server rpcbind` on the
  host first, then retry.
- **"NFS server is not running" (exit 114)** / `Not starting NFS kernel daemon: no support in
  current kernel` — `nfsd` is a kernel service. The container has the userspace tools but no
  `modprobe` and no `/lib/modules`, so it cannot load the module itself; it needs the *host* kernel
  to have `nfsd` loaded. `flash.sh` now does `modprobe nfsd` automatically. Manual check:
  `lsmod | grep nfsd`, load with `sudo modprobe nfsd`. Note the host does **not** need `nfs-utils`
  installed and does **not** need an `/etc/exports` — only the kernel module. Arch ships the module
  with the kernel package but does not load it until something asks for NFS.
- **`... requires root privilege` / exit 207 right after "Step 1: Generate flash packages"** — the
  BSP gates on the `$USER` env var, not the real uid (`l4t_create_images_for_kernel_flash.sh:562`,
  `l4t_flash_from_kernel.sh:1372`, `flash.sh:2192`). Docker doesn't set `$USER`, so it aborts even
  as uid 0. Fixed with `ENV USER=root` in the Dockerfile — needs a rebuild (`sudo ./setup.sh`, or
  `docker build -t jp6-flash:latest scripts/`) if you're on an image built before that was added.
- **`docker build` fails with `no permission to read from .../Linux_for_Tegra/rootfs/etc/.pwd.lock`**
  — the build context picked up the extracted 11GB root-owned BSP. `.dockerignore` excludes it now
  (it's bind-mounted at run time, never copied in). Also makes rebuilds near-instant.
- **`gzip: .../kernel/Image: not in gzip format` — harmless, ignore it.** That's
  `ota_make_recovery_img_dtb.sh:173` (`if gzip -t "$_kernel_fs"`) *testing* whether the kernel is
  compressed. This BSP ships an uncompressed ARM64 `Image`, so the test correctly fails and the
  decompress branch is skipped. It prints to stderr on every run, including successful ones.
- **`command is failed` / `Error: failed to generate images` right after `_BASE_KERNEL_VERSION=`**
  — missing `ssh-keygen`. `ota_make_recovery_img_dtb.sh:112-115` generates the recovery initrd's
  SSH host keys behind a *bare* `check_error`, so the real cause is never named. `openssh-client`
  is absent from the vendored prerequisites list; it's in the Dockerfile now. The host also needs
  `ssh` itself later, to reach the booted target over IPv6 link-local.
- **`esp.img: failed to set up loop device: No such file or directory`** — image generation attaches
  several loop devices at once (`flash.sh:1537`). Docker hands the container its own `/dev` tmpfs
  snapshot, so the `/dev/loop1` the kernel auto-creates for the second attach lands in the host
  devtmpfs and is invisible inside the container. Fixed by `-v /dev:/dev` in `flash.sh` (replaces
  the narrower `-v /dev/bus/usb:/dev/bus/usb`, which it also covers).
- Stale loop attachments survive the container. `losetup -a` to check, and to clear one without
  host root: `docker run --rm --privileged -v /dev:/dev jp6-flash:latest losetup -d /dev/loopN`.

## Validating without touching the board
Image generation is the half that keeps breaking, and it can be exercised on its own — `--no-flash`
builds the ~2.7GB flash package and never writes to the target:

```bash
cd scripts
docker run --rm --privileged --net=host -v /dev:/dev \
  -v "$PWD/Linux_for_Tegra:/work" -w /work jp6-flash:latest \
  ./tools/kernel_flash/l4t_initrd_flash.sh --no-flash \
    --external-device nvme0n1p1 -c tools/kernel_flash/flash_l4t_t234_nvme.xml \
    -p "-c bootloader/generic/cfg/flash_t234_qspi.xml" --showlogs --network usb0 \
    jetson-orin-nano-devkit-super-nvme internal
```

Success ends with `Finish generating flash package.` and exit 0. Once that package exists, adding
`--flash-only` (instead of `--no-flash`) flashes it without regenerating.
