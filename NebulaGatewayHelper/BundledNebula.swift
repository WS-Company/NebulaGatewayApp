// BundledNebula.swift
// NebulaGatewayHelper
//
// The nebula shipped in Contents/Helpers of the app bundle (official release, fetched by tools/fetch-nebula.sh).
// The helper runs its root-owned copy only if the copy matches this hash. Keep in sync with NEBULA_SHA256 there.

enum BundledNebula {
    static let version = "1.11.2"
    static let sha256 = "b2eec15124d83774e5831baeabfca6283f90c950143e21334ed2522c793e9038"
}
