// FileValidator.swift
// NebulaGateway

import Foundation

/// Validates Nebula configuration files, certificates, and keys.
struct FileValidator {

    enum ValidationError: LocalizedError {
        case fileNotFound(String)
        case fileNotReadable(String)
        case fileTooLarge(String, UInt64)
        case fileEmpty(String)
        case invalidYAML(String, String)
        case missingYAMLKey(String, String)
        case invalidCertificate(String)
        case invalidKey(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let path):
                return "File not found: \(path)"
            case .fileNotReadable(let path):
                return "File not readable: \(path)"
            case .fileTooLarge(let path, let size):
                return "File too large (\(size) bytes): \(path)"
            case .fileEmpty(let path):
                return "File is empty: \(path)"
            case .invalidYAML(let path, let reason):
                return "Invalid YAML in \(path): \(reason)"
            case .missingYAMLKey(let path, let key):
                return "Missing required key '\(key)' in \(path)"
            case .invalidCertificate(let path):
                return "Invalid Nebula certificate: \(path)"
            case .invalidKey(let path):
                return "Invalid Nebula key: \(path)"
            }
        }
    }

    private let fileManager = FileManager.default
    private let log = AppLogger.shared

    // MARK: - Public API

    /// Validates a Nebula config.yml file.
    /// Returns the list of errors found (empty = valid).
    func validateConfig(at path: String) -> [ValidationError] {
        var errors: [ValidationError] = []
        let expandedPath = (path as NSString).expandingTildeInPath

        // Basic file checks
        if let fileError = checkFileExists(expandedPath, maxSize: 1_000_000) {
            return [fileError]
        }

        // YAML parsing
        guard let content = try? String(contentsOfFile: expandedPath, encoding: .utf8) else {
            return [.fileNotReadable(expandedPath)]
        }

        // Check for required top-level keys
        let requiredKeys = ["pki", "static_host_map", "lighthouse", "listen", "tun", "firewall"]
        for key in requiredKeys {
            // Simple check: the key should appear at the start of a line (top-level YAML)
            let pattern = "(?m)^" + NSRegularExpression.escapedPattern(for: key) + ":"
            if content.range(of: pattern, options: .regularExpression) == nil {
                errors.append(.missingYAMLKey(expandedPath, key))
            }
        }

        // Check PKI file references
        if let pkiErrors = validatePKIReferences(in: content, configDir: (expandedPath as NSString).deletingLastPathComponent) {
            errors.append(contentsOf: pkiErrors)
        }

        errors.forEach { log.warning("Config validation: \($0.localizedDescription)") }
        return errors
    }

    /// Validates a Nebula certificate file (.crt).
    func validateCertificate(at path: String) -> ValidationError? {
        let expanded = (path as NSString).expandingTildeInPath

        if let fileError = checkFileExists(expanded, maxSize: 100_000) {
            return fileError
        }

        guard let content = try? String(contentsOfFile: expanded, encoding: .utf8) else {
            return .fileNotReadable(expanded)
        }

        // Nebula certs start with a specific PEM header or are raw binary
        let validHeaders = ["-----BEGIN NEBULA CERTIFICATE-----", "-----BEGIN NEBULA ED25519"]
        let hasValidHeader = validHeaders.contains { content.hasPrefix($0) }
        if !hasValidHeader && content.count < 32 {
            return .invalidCertificate(expanded)
        }

        return nil
    }

    /// Validates a Nebula private key file (.key).
    func validateKey(at path: String) -> ValidationError? {
        let expanded = (path as NSString).expandingTildeInPath

        if let fileError = checkFileExists(expanded, maxSize: 10_000) {
            return fileError
        }

        guard let content = try? String(contentsOfFile: expanded, encoding: .utf8) else {
            return .fileNotReadable(expanded)
        }

        let validHeaders = ["-----BEGIN NEBULA X25519", "-----BEGIN NEBULA ED25519"]
        let hasValidHeader = validHeaders.contains { content.contains($0) }
        if !hasValidHeader && content.count < 16 {
            return .invalidKey(expanded)
        }

        return nil
    }

    /// Full validation of a connection's config and all referenced files.
    func validateConnection(_ config: ConnectionConfig) -> [ValidationError] {
        var errors = validateConfig(at: config.configPath)

        if config.localStorage {
            let dir = config.configDirectory
            let certFiles: [(String, (String) -> ValidationError?)] = [
                (Constants.NebulaFiles.caCert, validateCertificate),
                (Constants.NebulaFiles.nodeCert, validateCertificate),
                (Constants.NebulaFiles.nodeKey, validateKey),
            ]
            for (filename, validator) in certFiles {
                let filePath = dir.appendingPathComponent(filename).path
                if let error = validator(filePath) {
                    errors.append(error)
                }
            }
        }

        return errors
    }

    // MARK: - Private

    private func checkFileExists(_ path: String, maxSize: UInt64) -> ValidationError? {
        guard fileManager.fileExists(atPath: path) else {
            return .fileNotFound(path)
        }
        guard fileManager.isReadableFile(atPath: path) else {
            return .fileNotReadable(path)
        }
        guard let attrs = try? fileManager.attributesOfItem(atPath: path),
              let size = attrs[.size] as? UInt64
        else {
            return .fileNotReadable(path)
        }
        if size == 0 {
            return .fileEmpty(path)
        }
        if size > maxSize {
            return .fileTooLarge(path, size)
        }
        return nil
    }

    private func validatePKIReferences(in yamlContent: String, configDir: String) -> [ValidationError]? {
        var errors: [ValidationError] = []

        let pkiKeys = ["ca", "cert", "key"]
        for key in pkiKeys {
            // Match "ca: /path/to/file" or "  ca: /path/to/file" under pki:
            let pattern = "(?m)^\\s+\(key):\\s+(.+)$"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: yamlContent, range: NSRange(yamlContent.startIndex..., in: yamlContent)),
                  let pathRange = Range(match.range(at: 1), in: yamlContent)
            else {
                continue
            }

            var filePath = String(yamlContent[pathRange]).trimmingCharacters(in: .whitespaces)
            filePath = (filePath as NSString).expandingTildeInPath

            if !filePath.hasPrefix("/") {
                filePath = (configDir as NSString).appendingPathComponent(filePath)
            }

            if !fileManager.fileExists(atPath: filePath) {
                errors.append(.fileNotFound(filePath))
            }
        }

        return errors.isEmpty ? nil : errors
    }
}
