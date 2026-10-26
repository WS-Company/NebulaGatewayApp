// NebulaBinaryLocator.swift
// NebulaGateway

import Foundation

/// Locates the Nebula binaries shipped inside the app (Contents/Helpers).
/// The helper runs its own root-owned copy of `nebula`; the app uses these paths for the version and `nebula-cert`.
struct NebulaBinaryLocator {

    struct Result {
        let path: String
        let certPath: String
        let version: String
        let source: Source
    }

    enum Source: String {
        case bundled = "Bundled"
    }

    private let fileManager = FileManager.default
    private let log = AppLogger.shared

    /// Find the bundled Nebula binary.
    /// Returns nil if it is missing from the app bundle.
    func locate() -> Result? {
        let bundle = Bundle.main.bundleURL
        let path = bundle.appendingPathComponent(Constants.NebulaBinary.bundledSubpath).path
        let certPath = bundle.appendingPathComponent(Constants.NebulaBinary.bundledCertSubpath).path

        if let result = verify(path: path, certPath: certPath) {
            log.info("Using bundled Nebula at \(path) (v\(result.version))")
            return result
        }

        log.error("No Nebula binary found in the app bundle")
        return nil
    }

    // MARK: - Private

    private func verify(path: String, certPath: String) -> Result? {
        guard fileManager.isExecutableFile(atPath: path) else {
            return nil
        }

        guard let version = queryVersion(path: path) else {
            log.warning("Found Nebula at \(path) but failed to get version")
            return nil
        }

        return Result(path: path, certPath: certPath, version: version, source: .bundled)
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
