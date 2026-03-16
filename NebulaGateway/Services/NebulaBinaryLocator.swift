// NebulaBinaryLocator.swift
// NebulaGateway

import Foundation

/// Locates the Nebula binary on the system.
/// Priority: Homebrew installation > bundled binary in app resources.
struct NebulaBinaryLocator {

    struct Result {
        let path: String
        let version: String
        let source: Source
    }

    enum Source: String {
        case homebrew = "Homebrew"
        case bundled = "Bundled"
    }

    private let fileManager = FileManager.default
    private let log = AppLogger.shared

    /// Find the best available Nebula binary.
    /// Returns nil if no binary is found.
    func locate() -> Result? {
        // 1. Check Homebrew paths
        for brewPath in Constants.NebulaBinary.allBrewPaths {
            if let result = verify(path: brewPath, source: .homebrew) {
                log.info("Using Homebrew Nebula at \(brewPath) (v\(result.version))")
                return result
            }
        }

        // 2. Check bundled binary
        if let bundlePath = Bundle.main.path(forResource: "nebula", ofType: nil) {
            if let result = verify(path: bundlePath, source: .bundled) {
                log.info("Using bundled Nebula at \(bundlePath) (v\(result.version))")
                return result
            }
        }

        log.error("No Nebula binary found")
        return nil
    }

    // MARK: - Private

    private func verify(path: String, source: Source) -> Result? {
        guard fileManager.isExecutableFile(atPath: path) else {
            return nil
        }

        guard let version = queryVersion(path: path) else {
            log.warning("Found Nebula at \(path) but failed to get version")
            return nil
        }

        return Result(path: path, version: version, source: source)
    }

    /// Runs `nebula --version` and parses the output.
    private func queryVersion(path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else {
            return nil
        }

        // Output format: "Version: 1.10.3"
        return output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "Version: ", with: "")
    }
}
