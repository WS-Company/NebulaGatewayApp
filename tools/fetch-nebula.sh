#!/bin/bash
# Fetches the official nebula release for macOS into Vendor/nebula/.
# The app bundles these binaries; the helper runs nebula only if its sha256
# matches BundledNebula.sha256 (NebulaGatewayHelper/BundledNebula.swift).
# To change the version, update all four values below and BundledNebula.swift.
set -euo pipefail

VERSION="v1.12.0"
ZIP_SHA256="fa9c408ec42bfd7391055ab81fb8571d4f27a046aa82481e8dab6230205a049a"
NEBULA_SHA256="e4bd2008c52c7fe7696700e4704a00e4d8d505559c4348c366bd2301f9dfcaa2"
NEBULA_CERT_SHA256="f4687e46fa5215a69be40089a26e9f2c33ddcee544e580a49d7585143a1d5b72"

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
