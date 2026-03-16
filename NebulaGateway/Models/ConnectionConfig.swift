// ConnectionConfig.swift
// NebulaGateway

import Foundation

/// Persistent configuration for a single Nebula connection.
/// Stored in the app's config.toml.
struct ConnectionConfig: Identifiable, Codable, Equatable {

    /// Unique stable identifier (e.g. "connection_1").
    var id: String

    /// User-visible connection name (e.g. "Work VPN").
    var name: String

    /// Absolute path to the Nebula config.yml file.
    var configPath: String

    /// Whether the config and certs have been copied into local app storage.
    var localStorage: Bool

    /// Whether to start this connection automatically on app launch.
    var autostart: Bool

    // MARK: - Derived paths (read from Nebula YAML at runtime, not persisted)

    /// Resolves the config URL, expanding tilde if needed.
    var configURL: URL {
        URL(fileURLWithPath: (configPath as NSString).expandingTildeInPath)
    }

    /// Directory containing the config file.
    var configDirectory: URL {
        configURL.deletingLastPathComponent()
    }

    // MARK: - Factory

    /// Creates a new connection with the next available sequential ID.
    static func create(name: String, configPath: String, existingIds: [String]) -> ConnectionConfig {
        let maxNumber = existingIds.compactMap { id -> Int? in
            guard id.hasPrefix("connection_") else { return nil }
            return Int(id.dropFirst("connection_".count))
        }.max() ?? 0

        return ConnectionConfig(
            id: "connection_\(maxNumber + 1)",
            name: name,
            configPath: configPath,
            localStorage: false,
            autostart: false
        )
    }
}
