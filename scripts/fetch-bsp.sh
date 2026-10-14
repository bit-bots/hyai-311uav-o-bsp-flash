#!/usr/bin/env bash
# Download the HZHY vendor BSP archive from the bit-bots mirror into software-design/ and verify it
# against CHECKSUMS.txt. Resumable: re-run after an interrupted download and it continues.
# Usage: ./fetch-bsp.sh        (JetPack 6.2, what setup.sh uses)
#        ./fetch-bsp.sh jp5    (JetPack 5.1.4, not flash-tested, setup.sh doesn't use it)
# No root needed — run this before `sudo ./setup.sh`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
MIRROR="https://data.bit-bots.de/jetson/jetpack/hyai-311uav-o"

case "${1:-jp6}" in
    jp6) dir=jp6; name="flash-311UAV-O-V2.0_ONX_Jp6.2_SC_v1.0.0_20251204.tar.gz" ;;
    jp5) dir=jp5; name="flash-AI311UAV-O_V2.0_ONX_Jp5.1.4_SC_v1.0.0_20251205-uartok.tar.gz" ;;
    *) echo "Usage: $0 [jp6|jp5]" >&2; exit 1 ;;
esac

dest="$REPO_ROOT/software-design/$name"
mkdir -p "$(dirname "$dest")"

echo "Downloading $name (resumes if partial)..."
curl -fL --retry 5 -C - -o "$dest" "$MIRROR/$dir/$name"

echo "Verifying sha256..."
if ! grep "  $name\$" "$REPO_ROOT/CHECKSUMS.txt" | (cd "$(dirname "$dest")" && sha256sum -c -); then
    rm -f "$dest"
    echo "Checksum mismatch — deleted $dest. Re-run to download again." >&2
    exit 1
fi

echo
echo "Done. Next: sudo ./setup.sh"
