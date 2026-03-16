// Logger.swift
// NebulaGateway

import Foundation
import OSLog

/// Unified logger that writes to both os_log and a user-accessible file.
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
            if !FileManager.default.fileExists(atPath: logFile.path) {
                FileManager.default.createFile(atPath: logFile.path, contents: nil)
            }
            Self.rotateIfNeeded(logFile)
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

    private static func rotateIfNeeded(_ logFile: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFile.path),
              let size = attrs[.size] as? UInt64,
              size > Constants.Logging.maxFileSize
        else { return }

        let fm = FileManager.default
        let dir = logFile.deletingLastPathComponent()
        let name = logFile.deletingPathExtension().lastPathComponent
        let ext = logFile.pathExtension

        // Shift existing rotated files
        for i in stride(from: Constants.Logging.maxFileCount - 1, through: 1, by: -1) {
            let src = dir.appendingPathComponent("\(name).\(i).\(ext)")
            let dst = dir.appendingPathComponent("\(name).\(i + 1).\(ext)")
            try? fm.removeItem(at: dst)
            try? fm.moveItem(at: src, to: dst)
        }

        let rotated = dir.appendingPathComponent("\(name).1.\(ext)")
        try? fm.moveItem(at: logFile, to: rotated)
        fm.createFile(atPath: logFile.path, contents: nil)
    }
}
