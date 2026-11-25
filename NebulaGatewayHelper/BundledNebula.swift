// BundledNebula.swift
// NebulaGatewayHelper
//
// The nebula shipped in Contents/Helpers of the app bundle (official release, fetched by tools/fetch-nebula.sh).
// The helper runs its root-owned copy only if the copy matches this hash. Keep in sync with NEBULA_SHA256 there.

enum BundledNebula {
    static let version = "1.12.0"
    static let sha256 = "e4bd2008c52c7fe7696700e4704a00e4d8d505559c4348c366bd2301f9dfcaa2"
}
