// NebulaConfigParser.swift
// NebulaGateway

import Foundation

/// Parses Nebula YAML configuration files to extract PKI paths, network info, and other settings.
/// Uses line-by-line parsing to avoid heavy YAML library dependency for simple reads.
struct NebulaConfigParser {

    /// Extracted data from a Nebula config.
    struct ParsedConfig {
        var caPath: String?
        var certPath: String?
        var keyPath: String?
        var nebulaIP: String?
        var listenPort: Int?
        var interfaceName: String?
        var lighthouseHosts: [String] = []
    }

    enum ParseError: LocalizedError {
        case fileNotReadable(String)
        case malformedYAML(String)

        var errorDescription: String? {
            switch self {
            case .fileNotReadable(let path): return "Cannot read config at \(path)"
            case .malformedYAML(let detail): return "Malformed YAML: \(detail)"
            }
        }
    }

    private let log = AppLogger.shared

    // MARK: - Public API

    /// Parse a Nebula config.yml and extract key fields.
    func parse(at path: String) throws -> ParsedConfig {
        let expanded = (path as NSString).expandingTildeInPath

        guard let content = try? String(contentsOfFile: expanded, encoding: .utf8) else {
            throw ParseError.fileNotReadable(expanded)
        }

        var config = ParsedConfig()
        let lines = content.components(separatedBy: .newlines)

        var currentSection = ""
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Track top-level sections (no leading whitespace, ends with colon)
            if !line.hasPrefix(" ") && !line.hasPrefix("\t") && trimmed.hasSuffix(":") && !trimmed.contains(" ") {
                currentSection = String(trimmed.dropLast())
                continue
            }

            // Extract values based on current section
            switch currentSection {
            case "pki":
                if let value = extractValue(trimmed, key: "ca") {
                    config.caPath = resolvePath(value, relativeTo: expanded)
                } else if let value = extractValue(trimmed, key: "cert") {
                    config.certPath = resolvePath(value, relativeTo: expanded)
                } else if let value = extractValue(trimmed, key: "key") {
                    config.keyPath = resolvePath(value, relativeTo: expanded)
                }

            case "listen":
                if let value = extractValue(trimmed, key: "port") {
                    config.listenPort = Int(value)
                }

            case "tun":
                if let value = extractValue(trimmed, key: "dev") {
                    config.interfaceName = value
                }

            default:
                break
            }

            // Lighthouse hosts (nested under lighthouse.hosts)
            if trimmed.hasPrefix("- \"10.") && currentSection == "lighthouse" {
                let host = trimmed
                    .replacingOccurrences(of: "- ", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                config.lighthouseHosts.append(host)
            }
        }

        log.debug("Parsed config at \(path): PKI ca=\(config.caPath ?? "nil"), cert=\(config.certPath ?? "nil")")
        return config
    }

    /// Extract the Nebula IP from a certificate file using nebula-cert print.
    func extractIP(fromCert certPath: String, nebulaBinary: String) -> String? {
        let certBinary = nebulaBinary.replacingOccurrences(of: "/nebula", with: "/nebula-cert")
        let expanded = (certPath as NSString).expandingTildeInPath

        guard FileManager.default.isExecutableFile(atPath: certBinary) else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: certBinary)
        process.arguments = ["print", "-path", expanded, "-json"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard let data = try? pipe.fileHandleForReading.readDataToEndOfFile(),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let details = json["details"] as? [String: Any],
              let networks = details["networks"] as? [String],
              let firstNetwork = networks.first
        else {
            return nil
        }

        // "10.10.10.10/8" → "10.10.10.10"
        return firstNetwork.components(separatedBy: "/").first
    }

    /// Rewrites PKI paths in a config file to point to new locations.
    func rewritePKIPaths(
        configPath: String,
        caPath: String,
        certPath: String,
        keyPath: String
    ) throws {
        let expanded = (configPath as NSString).expandingTildeInPath

        guard var content = try? String(contentsOfFile: expanded, encoding: .utf8) else {
            throw ParseError.fileNotReadable(expanded)
        }

        content = replacePKIValue(in: content, key: "ca", newValue: caPath)
        content = replacePKIValue(in: content, key: "cert", newValue: certPath)
        content = replacePKIValue(in: content, key: "key", newValue: keyPath)

        try content.write(toFile: expanded, atomically: true, encoding: .utf8)
        log.info("Rewrote PKI paths in \(expanded)")
    }

    // MARK: - Private

    private func extractValue(_ line: String, key: String) -> String? {
        let prefix = "\(key):"
        guard line.hasPrefix(prefix) else { return nil }
        let value = String(line.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\"", with: "")
        return value.isEmpty ? nil : value
    }

    private func resolvePath(_ path: String, relativeTo configPath: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return expanded }
        let configDir = (configPath as NSString).deletingLastPathComponent
        return (configDir as NSString).appendingPathComponent(expanded)
    }

    private func replacePKIValue(in content: String, key: String, newValue: String) -> String {
        // Match lines like "  ca: /old/path" or "  cert: /old/path"
        let pattern = "(\\s+\(key):\\s+).+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return content }
        let range = NSRange(content.startIndex..., in: content)
        return regex.stringByReplacingMatches(in: content, range: range, withTemplate: "$1\(newValue)")
    }
}
