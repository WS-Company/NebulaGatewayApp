#!/bin/bash
# Fetches the official nebula release for macOS into Vendor/nebula/.
# The app bundles these binaries; the helper runs nebula only if its sha256
# matches BundledNebula.sha256 (NebulaGatewayHelper/BundledNebula.swift).
# To change the version, update all four values below and BundledNebula.swift.
set -euo pipefail

VERSION="v1.11.2"
ZIP_SHA256="ae23ebd29e570d72f28d71e608261d454fb87b1a19b4ca21c2aa26bb4698da88"
NEBULA_SHA256="b2eec15124d83774e5831baeabfca6283f90c950143e21334ed2522c793e9038"
NEBULA_CERT_SHA256="af3d5cb8bbd07ba33994172a679b278dda9a5ffc04f3173c7f581e6aea14c6a1"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor/nebula"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fsSL -o "$TMP/nebula-darwin.zip" \
    "https://github.com/slackhq/nebula/releases/download/$VERSION/nebula-darwin.zip"

check() {
    local actual
    actual="$(shasum -a 256 "$1" | cut -d' ' -f1)"
    if [ "$actual" != "$2" ]; then
        echo "sha256 mismatch for $1: $actual" >&2
        exit 1
    fi
}

check "$TMP/nebula-darwin.zip" "$ZIP_SHA256"
unzip -q "$TMP/nebula-darwin.zip" nebula nebula-cert -d "$TMP/x"
check "$TMP/x/nebula" "$NEBULA_SHA256"
check "$TMP/x/nebula-cert" "$NEBULA_CERT_SHA256"

mkdir -p "$DEST"
install -m 0755 "$TMP/x/nebula" "$TMP/x/nebula-cert" "$DEST/"
echo "nebula $VERSION -> $DEST"
