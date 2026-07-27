#!/usr/bin/env bash
#
# Build / test helper for DH Tracker.
#
#   ./build.sh                  release build for every product in manifest.xml
#   ./build.sh fenix7pro        release build for one product
#   ./build.sh --test           unit-test build (needs the simulator to run)
#   ./build.sh --run fenix7pro  build + push to a running simulator
#
# Requires the Connect IQ SDK: set SDK_HOME, or install it with the SDK Manager
# (the default path below is what the manager uses).
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRODUCTS=(fenix7 fenix7s fenix7x
          fenix7pro fenix7spro fenix7xpro
          fenix7pronowifi fenix7xpronowifi)
TYPECHECK="${TYPECHECK:-3}"   # 0=off 1=gradual 2=informative 3=strict

if [[ -z "${SDK_HOME:-}" ]]; then
    CFG="$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg"
    if [[ -f "$CFG" ]]; then
        SDK_HOME="$(tr -d '\n' < "$CFG")"
    else
        echo "SDK not found. Set SDK_HOME or install the Connect IQ SDK Manager." >&2
        exit 1
    fi
fi

KEY="${DEVELOPER_KEY:-$PROJECT_DIR/developer_key.der}"
if [[ ! -f "$KEY" ]]; then
    echo "Generating a developer key at $KEY"
    openssl genrsa -out "${KEY%.der}.pem" 4096 2>/dev/null
    openssl pkcs8 -topk8 -inform PEM -outform DER \
        -in "${KEY%.der}.pem" -out "$KEY" -nocrypt
fi

mkdir -p "$PROJECT_DIR/bin"

build() { # <device> <output> [extra monkeyc args...]
    local device="$1" output="$2"; shift 2
    echo "==> $device"
    "$SDK_HOME/bin/monkeyc" \
        -f "$PROJECT_DIR/monkey.jungle" \
        -d "$device" \
        -o "$output" \
        -y "$KEY" \
        -w -l "$TYPECHECK" "$@"
}

case "${1:-}" in
    --test)
        device="${2:-fenix7pro}"
        build "$device" "$PROJECT_DIR/bin/dh-tracker-test.prg" --unit-test
        echo
        echo "Start the simulator ('\$SDK_HOME/bin/connectiq'), then run:"
        echo "  \"\$SDK_HOME/bin/monkeydo\" bin/dh-tracker-test.prg $device -t"
        ;;
    --run)
        device="${2:-fenix7pro}"
        build "$device" "$PROJECT_DIR/bin/dh-tracker.prg" -g
        "$SDK_HOME/bin/monkeydo" "$PROJECT_DIR/bin/dh-tracker.prg" "$device"
        ;;
    "")
        for device in "${PRODUCTS[@]}"; do
            build "$device" "$PROJECT_DIR/bin/dh-tracker-$device.prg" -r
        done
        ;;
    *)
        build "$1" "$PROJECT_DIR/bin/dh-tracker-$1.prg" -r
        ;;
esac
