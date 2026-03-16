// AppConfiguration.swift
// NebulaGateway

import Foundation

/// Root model representing the entire app configuration (config.toml).
struct AppConfiguration: Codable, Equatable {

    struct AppMeta: Codable, Equatable {
        var version: String = "1.0.0"
        var firstRun: Bool = true

        enum CodingKeys: String, CodingKey {
            case version
            case firstRun = "first_run"
        }
    }

    var app: AppMeta = AppMeta()
    var connections: [ConnectionConfig] = []

    /// Default empty configuration for first launch.
    static let `default` = AppConfiguration()
}
