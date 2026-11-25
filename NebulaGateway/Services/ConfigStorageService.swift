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
    /// The chosen file is parsed where it lies, so its relative PKI paths resolve beside it, and nothing in
    /// the storage is touched until every source file is known to be there.
    func reimportConfig(for connection: inout ConnectionConfig, newConfigPath: URL) throws {
        let connectionDir = Constants.Paths.connections.appendingPathComponent(connection.id)
        let dstConfig = connectionDir.appendingPathComponent(Constants.NebulaFiles.config)

        let parsed = try parser.parse(at: newConfigPath.path)

        let pkiMappings: [(source: String?, destination: String)] = [
            (parsed.caPath, Constants.NebulaFiles.caCert),
            (parsed.certPath, Constants.NebulaFiles.nodeCert),
            (parsed.keyPath, Constants.NebulaFiles.nodeKey),
        ]
        var copies: [(from: URL, name: String)] = [(newConfigPath, Constants.NebulaFiles.config)]
        for mapping in pkiMappings {
            guard let srcPath = mapping.source else {
                throw NebulaConfigParser.ParseError.malformedYAML("Missing PKI path for \(mapping.destination)")
            }
            copies.append((URL(fileURLWithPath: srcPath), mapping.destination))
        }

        // Everything is prepared in a staging folder first; the stored files are replaced only once the new
        // set is complete. A source may be a stored file itself (under any spelling of its path): it is
        // copied before anything is replaced.
        let staging = connectionDir.appendingPathComponent(".reimport-\(UUID().uuidString)")
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        for copy in copies {
            try fileManager.copyItem(at: copy.from, to: staging.appendingPathComponent(copy.name))
        }
        try parser.rewritePKIPaths(
            configPath: staging.appendingPathComponent(Constants.NebulaFiles.config).path,
            caPath: connectionDir.appendingPathComponent(Constants.NebulaFiles.caCert).path,
            certPath: connectionDir.appendingPathComponent(Constants.NebulaFiles.nodeCert).path,
            keyPath: connectionDir.appendingPathComponent(Constants.NebulaFiles.nodeKey).path
        )

        for copy in copies {
            _ = try fileManager.replaceItemAt(
                connectionDir.appendingPathComponent(copy.name),
                withItemAt: staging.appendingPathComponent(copy.name)
            )
        }

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
