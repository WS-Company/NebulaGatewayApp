// Constants.swift
// NebulaGateway

import Foundation

enum Constants {

    static let appName = "Nebula Gateway"
    static let appBundleId = "com.nebulagateway.app"
    static let helperBundleId = "com.nebulagateway.helper"
    static let githubURL = URL(string: "https://github.com/WS-Company/NebulaGatewayApp")!
    static let nebulaGithubURL = URL(string: "https://github.com/slackhq/nebula")!

    // MARK: - Storage Paths

    enum Paths {

        static var appSupport: URL {
            FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("Nebula Gateway")
        }

        static var logs: URL {
            FileManager.default
                .urls(for: .libraryDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("Logs/Nebula Gateway")
        }

        static var connections: URL {
            appSupport.appendingPathComponent("connections")
        }

        static var configFile: URL {
            appSupport.appendingPathComponent("config.toml")
        }
    }

    // MARK: - Standardized File Names

    enum NebulaFiles {
        static let config = "config.yml"
        static let caCert = "pki_ca.crt"
        static let nodeCert = "pki_cert.crt"
        static let nodeKey = "pki_key.key"
    }

    // MARK: - Nebula Binary Locations

    enum NebulaBinary {
        static let brewAppleSilicon = "/opt/homebrew/bin/nebula"
        static let brewIntel = "/usr/local/bin/nebula"
        static let bundledSubpath = "Contents/Resources/nebula"

        static var allBrewPaths: [String] {
            [brewAppleSilicon, brewIntel]
        }
    }

    // MARK: - Network Monitoring

    enum Monitoring {
        static let speedUpdateInterval: TimeInterval = 1.0
    }

    // MARK: - Logging

    enum Logging {
        static let appLogName = "app.log"
    }
}
