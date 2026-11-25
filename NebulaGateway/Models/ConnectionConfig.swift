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

    /// Whether the user wants this connection on. Start sets it, only Stop or Delete clears it: quitting the
    /// app, a reboot or nebula dying leave it, so the next launch brings the connection back.
    var connected: Bool

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
            connected: false
        )
    }

    /// The connections found running on launch; nobody switched them off, so they count as wanted on.
    static func idsRunning(_ connections: [ConnectionConfig], runningConfigPaths: Set<String>) -> [String] {
        connections.filter { runningConfigPaths.contains($0.configURL.path) }.map(\.id)
    }

    /// The connections to start on launch: wanted on, startable (in local storage) and not running already.
    /// `runningConfigPaths` is the helper's first answer; without it a config still running after a mere
    /// app quit would get a second nebula.
    static func idsToRestore(_ connections: [ConnectionConfig], runningConfigPaths: Set<String>) -> [String] {
        connections
            .filter { $0.connected && $0.localStorage && !runningConfigPaths.contains($0.configURL.path) }
            .map(\.id)
    }
}
