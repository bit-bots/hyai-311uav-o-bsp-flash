#!/usr/bin/env bash
# Post-flash setup for HYAI-311UAV-O (JetPack 6.2). Runs ON THE JETSON, not the flashing host.
# Idempotent: safe to re-run, a second run changes nothing.
#   1. Guard: disable unattended upgrades, motd warning, mute Ubuntu's update/ESM pitch
#   2. apt-mark hold the L4T/tegra packages (HZHY's custom kernel + adaptation layer)
#   3. Optional static IPv4 via NetworkManager (--ip)
#   4. Post-flash checks: PASS/FAIL/WARN/MANUAL, exit 1 only on FAIL
#
# Copy over + run (USB link, so a network change can't cut your session):
#   scp postflash.sh nvidia@192.168.55.1: && ssh -t nvidia@192.168.55.1 sudo ./postflash.sh [opts]
# Options:
#   --ip ADDR[/PREFIX]   static IPv4, prefix defaults to /22 (bit-bots: 172.20.1.1<robot number>)
#   --gw ADDR            gateway, default 172.20.0.1
#   --dns ADDR           DNS server, default 172.20.0.1
#   --iface DEV          ethernet device, default: first wired ethernet NetworkManager knows
set -euo pipefail

IP="" GW="172.20.0.1" DNS="172.20.0.1" IFACE=""
CON_NAME="postflash-static"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ip) IP="$2"; shift 2 ;;
        --gw) GW="$2"; shift 2 ;;
        --dns) DNS="$2"; shift 2 ;;
        --iface) IFACE="$2"; shift 2 ;;
        *) sed -n '2,16s/^# \?//p' "$0" >&2; exit 1 ;;
    esac
done

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo $0" >&2
    exit 1
fi

ipv4='([0-9]{1,3}\.){3}[0-9]{1,3}'
if [[ -n "$IP" ]]; then
    [[ "$IP" == */* ]] || IP="$IP/22"
    for v in "${IP%/*}" "$GW" "$DNS"; do
        [[ "$v" =~ ^$ipv4$ ]] || { echo "Not an IPv4 address: $v" >&2; exit 1; }
    done
    [[ "${IP#*/}" =~ ^[0-9]{1,2}$ ]] || { echo "Bad prefix: $IP" >&2; exit 1; }
fi

echo "== 1. Disable automatic upgrades =="
# Never `apt upgrade` this image: it overwrites HZHY's custom kernel (kernel/Image is rebuilt for
# this carrier board) and adaptation layer. Ubuntu ships unattended-upgrades enabled, so this can
# happen with nobody touching the board.
for unit in unattended-upgrades.service apt-daily.timer apt-daily-upgrade.timer; do
    systemctl disable --now "$unit" 2>/dev/null || true
done
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Unattended-Upgrade "0";
EOF

# 00- sorts before Ubuntu's own motd parts, so the warning comes first.
cat > /etc/update-motd.d/00-no-apt-upgrade <<'EOF'
#!/bin/sh
cat <<'MSG'

  !!! NEVER run `apt upgrade` on this board !!!
  HZHY's custom kernel and board adaptation layer would be overwritten.
  `sudo apt install <pkg>` (e.g. nvidia-jetpack) is fine.

MSG
EOF
chmod +x /etc/update-motd.d/00-no-apt-upgrade

for part in 88-esm-announce 90-updates-available 91-contract-ua-esm-status 91-release-upgrade; do
    if [[ -e "/etc/update-motd.d/$part" ]]; then chmod -x "/etc/update-motd.d/$part"; fi
done
command -v pro >/dev/null && pro config set apt_news=false >/dev/null 2>&1 || true

echo "== 2. Hold L4T/tegra packages =="
# Holds block upgrades of these, not installs of new packages. If a later
# `apt install nvidia-jetpack` complains about a held package: apt-mark unhold, install, re-run this.
mapfile -t held < <(dpkg-query -W -f='${Package}\n' | grep -E 'nvidia-l4t|tegra' || true)
if [[ ${#held[@]} -gt 0 ]]; then
    apt-mark hold "${held[@]}" >/dev/null
    echo "held ${#held[@]} packages"
else
    echo "no nvidia-l4t/tegra packages found"
fi

if [[ -n "$IP" ]]; then
    echo "== 3. Static IPv4: $IP gw $GW dns $DNS =="
    if [[ -z "$IFACE" ]]; then
        # l4tbr0 is the USB gadget bridge, usb*/rndis* its members; we want the real RJ45 port.
        IFACE="$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="ethernet" && $1!~/^(l4tbr|usb|rndis)/ {print $1; exit}')"
        [[ -n "$IFACE" ]] || { echo "No wired ethernet device found, pass --iface" >&2; exit 1; }
    fi
    echo "interface $IFACE (if you're SSH'd in over it, this session may drop)"
    nmcli -t -f NAME con show | grep -qx "$CON_NAME" \
        || nmcli con add type ethernet ifname "$IFACE" con-name "$CON_NAME" >/dev/null
    # autoconnect-priority beats the image's default DHCP profile on the same port.
    nmcli con modify "$CON_NAME" connection.interface-name "$IFACE" \
        ipv4.method manual ipv4.addresses "$IP" ipv4.gateway "$GW" ipv4.dns "$DNS" \
        ipv6.method ignore connection.autoconnect yes connection.autoconnect-priority 100
    nmcli con up "$CON_NAME" >/dev/null || echo "WARN: could not bring up $CON_NAME (cable plugged in?)"
else
    echo "== 3. Static IPv4: skipped (no --ip) =="
fi

echo "== 4. Checks =="
fails=0
report() {  # report STATUS what [detail]
    printf '%-6s %s%s\n' "$1" "$2" "${3:+ — $3}"
    [[ "$1" == FAIL ]] && fails=$((fails + 1))
    return 0
}

if grep -q 'R36' /etc/nv_tegra_release 2>/dev/null && grep -q 'REVISION: 4.3' /etc/nv_tegra_release; then
    report PASS "L4T 36.4.3 (JetPack 6.2)"
else
    report FAIL "L4T 36.4.3 (JetPack 6.2)" "$(head -1 /etc/nv_tegra_release 2>/dev/null || echo 'no /etc/nv_tegra_release')"
fi

root_src="$(findmnt -no SOURCE /)"
[[ "$root_src" == *nvme* ]] && report PASS "root on NVMe" "$root_src" || report FAIL "root on NVMe" "$root_src"

if systemctl is-enabled unattended-upgrades.service 2>/dev/null | grep -qx enabled; then
    report FAIL "unattended-upgrades disabled"
else
    report PASS "unattended-upgrades disabled"
fi
apt-mark showhold | grep -qx nvidia-l4t-kernel \
    && report PASS "nvidia-l4t-kernel held" || report FAIL "nvidia-l4t-kernel held"

default_route="$(ip route show default | head -1)"
gw_now="$(awk '{print $3}' <<<"$default_route")"
if [[ -z "$default_route" ]]; then
    report WARN "default route" "none"
elif [[ "$default_route" == *l4tbr0* ]]; then
    report WARN "default route" "via l4tbr0 (USB gadget) → no internet; plug into a router or use --ip"
else
    report PASS "default route" "$default_route"
    ping -c1 -W2 "$gw_now" >/dev/null 2>&1 \
        && report PASS "ping gateway $gw_now" || report WARN "ping gateway $gw_now"
fi

# Root hubs announce SuperSpeed themselves, so only a non-hub device at >=5000M counts.
usb3="$(lsusb -t 2>/dev/null | grep -E '(5000|10000|20000)M' | grep -vE 'root_hub|Class=Hub' | head -1 || true)"
[[ -n "$usb3" ]] && report PASS "USB3 device" "$(sed 's/^[ |_]*//' <<<"$usb3")" \
    || report WARN "USB3 device" "none at SuperSpeed; plug one into a USB3.0 port and re-run"

if ! command -v gpiodetect >/dev/null; then
    report WARN "GPIO (libgpiod)" "gpiodetect not installed (minimized image)"
elif gpiodetect >/dev/null 2>&1; then
    report PASS "GPIO (libgpiod)" "$(gpiodetect | wc -l) chips"
else
    report FAIL "GPIO (libgpiod)" "gpiodetect failed"
fi

compgen -G '/dev/video*' >/dev/null && report PASS "camera" "$(echo /dev/video*)" \
    || report WARN "camera" "no /dev/video* (none connected?)"

compgen -G '/sys/class/hwmon/*/pwm*' >/dev/null && report PASS "fan PWM node" \
    || report WARN "fan PWM node" "none in /sys/class/hwmon, fan ungoverned (ROADMAP #5)"

report MANUAL "HDMI output"
report MANUAL "debug UART J6" "115200 baud, console login"
report MANUAL "CAN J2" "CANalyst-II"
report MANUAL "RS232/TTL J11/J13" "9600 baud loopback"

echo
if [[ $fails -gt 0 ]]; then
    echo "$fails check(s) FAILED"
    exit 1
fi
echo "No failures. WARN/MANUAL items: see scripts/CHECKLIST.md §4."
