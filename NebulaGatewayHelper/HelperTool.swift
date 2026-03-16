// HelperTool.swift
// NebulaGatewayHelper

import Foundation

/// The privileged helper tool that runs as a LaunchDaemon.
/// Executes Nebula commands with root privileges on behalf of the main app.
final class HelperTool: NSObject, HelperProtocol, NSXPCListenerDelegate, @unchecked Sendable {

    private let version = "1.0.0"

    /// Maps PID → config path for tracking running Nebula processes.
    private var runningProcesses: [Int32: (process: Process, configPath: String)] = [:]
    private let processLock = NSLock()

    // MARK: - NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    // MARK: - HelperProtocol

    func startNebula(
        binaryPath: String,
        configPath: String,
        logPath: String,
        reply: @escaping (Bool, String) -> Void
    ) {
        // Validate paths — only allow nebula binary, not arbitrary executables
        guard isValidNebulaBinary(binaryPath) else {
            reply(false, "Invalid Nebula binary path")
            return
        }

        guard FileManager.default.fileExists(atPath: configPath) else {
            reply(false, "Config file not found: \(configPath)")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["-config", configPath]

        // Set up log redirection
        if let logFileHandle = createLogHandle(at: logPath) {
            process.standardOutput = logFileHandle
            process.standardError = logFileHandle
        }

        do {
            try process.run()
        } catch {
            reply(false, "Failed to start: \(error.localizedDescription)")
            return
        }

        let pid = process.processIdentifier

        processLock.lock()
        runningProcesses[pid] = (process, configPath)
        processLock.unlock()

        // Monitor for unexpected termination
        process.terminationHandler = { [weak self] proc in
            self?.processLock.lock()
            self?.runningProcesses.removeValue(forKey: proc.processIdentifier)
            self?.processLock.unlock()
        }

        reply(true, String(pid))
    }

    func stopNebula(pid: Int32, reply: @escaping (Bool, String) -> Void) {
        processLock.lock()
        guard let entry = runningProcesses[pid] else {
            processLock.unlock()
            // Try to kill by PID anyway (might have been started before helper)
            let result = kill(pid, SIGTERM)
            if result == 0 {
                reply(true, "Sent SIGTERM to PID \(pid)")
            } else {
                reply(false, "Process \(pid) not found")
            }
            return
        }

        let process = entry.process
        processLock.unlock()

        process.terminate()

        // Wait briefly for graceful shutdown
        DispatchQueue.global().async {
            var waited: TimeInterval = 0
            while process.isRunning && waited < 5.0 {
                Thread.sleep(forTimeInterval: 0.1)
                waited += 0.1
            }

            if process.isRunning {
                // Force kill
                kill(pid, SIGKILL)
                reply(true, "Force killed PID \(pid)")
            } else {
                reply(true, "Stopped PID \(pid)")
            }
        }
    }

    func getRunningProcesses(reply: @escaping ([String: String]) -> Void) {
        processLock.lock()
        defer { processLock.unlock() }

        var result: [String: String] = [:]
        for (pid, entry) in runningProcesses {
            if entry.process.isRunning {
                result[String(pid)] = entry.configPath
            }
        }
        reply(result)
    }

    func ping(reply: @escaping (String) -> Void) {
        reply(version)
    }

    // MARK: - Private

    private func isValidNebulaBinary(_ path: String) -> Bool {
        let allowedNames = ["nebula"]
        let fileName = (path as NSString).lastPathComponent
        return allowedNames.contains(fileName) && FileManager.default.isExecutableFile(atPath: path)
    }

    private func createLogHandle(at path: String) -> FileHandle? {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )

        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }

        return FileHandle(forWritingAtPath: path)
    }
}
