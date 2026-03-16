// ConfigStorageService.swift
// NebulaGateway

import Foundation

/// Manages the app's persistent configuration (config.toml) and
/// local storage of Nebula configs and certificates.
final class ConfigStorageService {

    private let log = AppLogger.shared
    private let fileManager = FileManager.default
    private let parser = NebulaConfigParser()

    // MARK: - Directory Setup

    /// Ensures all required directories exist.
    func ensureDirectories() {
        let dirs = [Constants.Paths.appSupport, Constants.Paths.connections, Constants.Paths.logs]
        for dir in dirs {
            if !fileManager.fileExists(atPath: dir.path) {
                do {
                    try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
                    log.info("Created directory: \(dir.path)")
                } catch {
                    log.error("Failed to create directory \(dir.path): \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Config Load / Save

    /// Loads the app configuration from config.toml.
    /// Returns default config if file doesn't exist yet.
    func loadConfig() -> AppConfiguration {
        let configURL = Constants.Paths.configFile

        guard fileManager.fileExists(atPath: configURL.path) else {
            log.info("No config file found, using defaults")
            return .default
        }

        do {
            let content = try String(contentsOf: configURL, encoding: .utf8)
            let config = try TOMLDecoder.decode(AppConfiguration.self, from: content)
            log.info("Loaded config with \(config.connections.count) connection(s)")
            return config
        } catch {
            log.error("Failed to load config: \(error.localizedDescription)")
            return .default
        }
    }

    /// Saves the app configuration to config.toml.
    func saveConfig(_ config: AppConfiguration) {
        let configURL = Constants.Paths.configFile

        do {
            let content = TOMLEncoder.encode(config)
            try content.write(to: configURL, atomically: true, encoding: .utf8)
            log.info("Saved config with \(config.connections.count) connection(s)")
        } catch {
            log.error("Failed to save config: \(error.localizedDescription)")
        }
    }

    // MARK: - Move to Local Storage

    /// Copies a connection's config and certificates into the app's local storage.
    /// Standardizes file names, rewrites PKI paths in config.yml.
    func moveToLocalStorage(_ connection: inout ConnectionConfig) throws {
        let connectionDir = Constants.Paths.connections
            .appendingPathComponent(connection.id)

        // Create connection directory
        try fileManager.createDirectory(at: connectionDir, withIntermediateDirectories: true)

        // Parse original config to find PKI file paths
        let parsed = try parser.parse(at: connection.configPath)

        // Copy config.yml
        let srcConfig = connection.configURL
        let dstConfig = connectionDir.appendingPathComponent(Constants.NebulaFiles.config)
        try copyFileOverwriting(from: srcConfig, to: dstConfig)

        // Copy PKI files with standardized names
        let pkiMappings: [(source: String?, destination: String)] = [
            (parsed.caPath, Constants.NebulaFiles.caCert),
            (parsed.certPath, Constants.NebulaFiles.nodeCert),
            (parsed.keyPath, Constants.NebulaFiles.nodeKey),
        ]

        for mapping in pkiMappings {
            guard let srcPath = mapping.source else {
                throw NebulaConfigParser.ParseError.malformedYAML("Missing PKI path for \(mapping.destination)")
            }
            let src = URL(fileURLWithPath: srcPath)
            let dst = connectionDir.appendingPathComponent(mapping.destination)
            try copyFileOverwriting(from: src, to: dst)
        }

        // Rewrite PKI paths in the copied config.yml to reference local files
        try parser.rewritePKIPaths(
            configPath: dstConfig.path,
            caPath: connectionDir.appendingPathComponent(Constants.NebulaFiles.caCert).path,
            certPath: connectionDir.appendingPathComponent(Constants.NebulaFiles.nodeCert).path,
            keyPath: connectionDir.appendingPathComponent(Constants.NebulaFiles.nodeKey).path
        )

        // Update connection to point to local storage
        connection.configPath = dstConfig.path
        connection.localStorage = true

        log.info("Moved connection '\(connection.name)' to local storage at \(connectionDir.path)")
    }

    /// Replaces a file in local storage (e.g., when user chooses a new config or cert).
    func replaceLocalFile(connectionId: String, standardName: String, from sourcePath: URL) throws {
        let dst = Constants.Paths.connections
            .appendingPathComponent(connectionId)
            .appendingPathComponent(standardName)
        try copyFileOverwriting(from: sourcePath, to: dst)
        log.info("Replaced \(standardName) for connection \(connectionId)")
    }

    /// Re-imports config and its PKI files when user chooses a new config.yml for a local-storage connection.
    func reimportConfig(for connection: inout ConnectionConfig, newConfigPath: URL) throws {
        let connectionDir = Constants.Paths.connections.appendingPathComponent(connection.id)
        let dstConfig = connectionDir.appendingPathComponent(Constants.NebulaFiles.config)

        // Copy new config
        try copyFileOverwriting(from: newConfigPath, to: dstConfig)

        // Parse and copy PKI files
        let parsed = try parser.parse(at: dstConfig.path)

        if let ca = parsed.caPath {
            try copyFileOverwriting(
                from: URL(fileURLWithPath: ca),
                to: connectionDir.appendingPathComponent(Constants.NebulaFiles.caCert)
            )
        }
        if let cert = parsed.certPath {
            try copyFileOverwriting(
                from: URL(fileURLWithPath: cert),
                to: connectionDir.appendingPathComponent(Constants.NebulaFiles.nodeCert)
            )
        }
        if let key = parsed.keyPath {
            try copyFileOverwriting(
                from: URL(fileURLWithPath: key),
                to: connectionDir.appendingPathComponent(Constants.NebulaFiles.nodeKey)
            )
        }

        // Rewrite paths
        try parser.rewritePKIPaths(
            configPath: dstConfig.path,
            caPath: connectionDir.appendingPathComponent(Constants.NebulaFiles.caCert).path,
            certPath: connectionDir.appendingPathComponent(Constants.NebulaFiles.nodeCert).path,
            keyPath: connectionDir.appendingPathComponent(Constants.NebulaFiles.nodeKey).path
        )

        connection.configPath = dstConfig.path
        log.info("Re-imported config for '\(connection.name)'")
    }

    // MARK: - Delete

    /// Deletes a connection's local storage directory.
    func deleteLocalStorage(for connectionId: String) {
        let dir = Constants.Paths.connections.appendingPathComponent(connectionId)
        do {
            if fileManager.fileExists(atPath: dir.path) {
                try fileManager.removeItem(at: dir)
                log.info("Deleted local storage for \(connectionId)")
            }
        } catch {
            log.error("Failed to delete local storage for \(connectionId): \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func copyFileOverwriting(from src: URL, to dst: URL) throws {
        if fileManager.fileExists(atPath: dst.path) {
            try fileManager.removeItem(at: dst)
        }
        try fileManager.copyItem(at: src, to: dst)
    }
}

// MARK: - Minimal TOML Encoder/Decoder

// Lightweight TOML handling for the simple config.toml structure.
// For production, consider replacing with TOMLKit SPM package.

enum TOMLDecoder {

    static func decode(_ type: AppConfiguration.Type, from content: String) throws -> AppConfiguration {
        var config = AppConfiguration()
        var currentConnection: ConnectionConfig?
        var connections: [ConnectionConfig] = []

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed == "[[connections]]" {
                if let conn = currentConnection {
                    connections.append(conn)
                }
                currentConnection = ConnectionConfig(
                    id: "", name: "", configPath: "", localStorage: false, autostart: false
                )
                continue
            }

            guard let (key, value) = parseKeyValue(trimmed) else { continue }

            if currentConnection != nil {
                switch key {
                case "id":           currentConnection?.id = value
                case "name":         currentConnection?.name = value
                case "config_path":  currentConnection?.configPath = value
                case "local_storage": currentConnection?.localStorage = (value == "true")
                case "autostart":    currentConnection?.autostart = (value == "true")
                default: break
                }
            } else {
                switch key {
                case "version":   config.app.version = value
                case "first_run": config.app.firstRun = (value == "true")
                default: break
                }
            }
        }

        if let conn = currentConnection {
            connections.append(conn)
        }
        config.connections = connections
        return config
    }

    private static func parseKeyValue(_ line: String) -> (String, String)? {
        guard let eqIndex = line.firstIndex(of: "=") else { return nil }
        let key = line[..<eqIndex].trimmingCharacters(in: .whitespaces)
        var value = line[line.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)
        // Strip quotes
        if value.hasPrefix("\"") && value.hasSuffix("\"") {
            value = String(value.dropFirst().dropLast())
        }
        return (key, value)
    }
}

enum TOMLEncoder {

    static func encode(_ config: AppConfiguration) -> String {
        var lines: [String] = [
            "# Nebula Gateway Configuration",
            "",
            "[app]",
            "version = \"\(config.app.version)\"",
            "first_run = \(config.app.firstRun)",
        ]

        for conn in config.connections {
            lines.append("")
            lines.append("[[connections]]")
            lines.append("id = \"\(conn.id)\"")
            lines.append("name = \"\(conn.name)\"")
            lines.append("config_path = \"\(conn.configPath)\"")
            lines.append("local_storage = \(conn.localStorage)")
            lines.append("autostart = \(conn.autostart)")
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }
}
