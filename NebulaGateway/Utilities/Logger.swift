// Logger.swift
// NebulaGateway

import Foundation
import OSLog

/// Unified logger that writes to both os_log and a user-accessible file.
/// Rotation: if the log file is older than 24 hours, it gets replaced on app launch.
final class AppLogger: @unchecked Sendable {

    static let shared = AppLogger()

    private let osLog = os.Logger(subsystem: Constants.appBundleId, category: "app")
    private let fileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.nebulagateway.logger", qos: .utility)
    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]
        return f
    }()

    private init() {
        let logDir = Constants.Paths.logs
        let logFile = logDir.appendingPathComponent(Constants.Logging.appLogName)

        do {
            try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
            Self.rotateIfOlderThan24Hours(logFile)
            if !FileManager.default.fileExists(atPath: logFile.path) {
                FileManager.default.createFile(atPath: logFile.path, contents: nil)
            }
            fileHandle = try FileHandle(forWritingTo: logFile)
            fileHandle?.seekToEndOfFile()
        } catch {
            fileHandle = nil
            os.Logger(subsystem: Constants.appBundleId, category: "app")
                .error("Failed to initialize file logger: \(error.localizedDescription)")
        }
    }

    deinit {
        try? fileHandle?.close()
    }

    // MARK: - Public API

    func debug(_ message: String, file: String = #fileID, function: String = #function) {
        log(level: .debug, message: message, file: file, function: function)
    }

    func info(_ message: String, file: String = #fileID, function: String = #function) {
        log(level: .info, message: message, file: file, function: function)
    }

    func warning(_ message: String, file: String = #fileID, function: String = #function) {
        log(level: .warning, message: message, file: file, function: function)
    }

    func error(_ message: String, file: String = #fileID, function: String = #function) {
        log(level: .error, message: message, file: file, function: function)
    }

    // MARK: - Internal

    private enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    private func log(level: Level, message: String, file: String, function: String) {
        let context = "\(file):\(function)"

        switch level {
        case .debug:   osLog.debug("[\(context)] \(message)")
        case .info:    osLog.info("[\(context)] \(message)")
        case .warning: osLog.warning("[\(context)] \(message)")
        case .error:   osLog.error("[\(context)] \(message)")
        }

        queue.async { [weak self] in
            self?.writeToFile(level: level, message: message, context: context)
        }
    }

    private func writeToFile(level: Level, message: String, context: String) {
        guard let fileHandle else { return }
        let timestamp = dateFormatter.string(from: Date())
        let line = "\(timestamp) [\(level.rawValue)] \(context) — \(message)\n"
        if let data = line.data(using: .utf8) {
            fileHandle.write(data)
        }
    }

    // MARK: - Log Rotation

    /// If the log file is older than 24 hours, delete it and start fresh.
    private static func rotateIfOlderThan24Hours(_ logFile: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: logFile.path),
              let attrs = try? fm.attributesOfItem(atPath: logFile.path),
              let modified = attrs[.modificationDate] as? Date
        else { return }

        let age = Date().timeIntervalSince(modified)
        if age > 24 * 60 * 60 {
            // Keep one backup
            let backup = logFile.deletingPathExtension()
                .appendingPathExtension("previous.log")
            try? fm.removeItem(at: backup)
            try? fm.moveItem(at: logFile, to: backup)
        }
    }
}
