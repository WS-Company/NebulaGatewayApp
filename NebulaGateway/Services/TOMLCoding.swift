// TOMLCoding.swift
// NebulaGateway

import Foundation

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
                    id: "", name: "", configPath: "", localStorage: false, connected: false
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
                case "connected":    currentConnection?.connected = (value == "true")
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
            lines.append("connected = \(conn.connected)")
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }
}
