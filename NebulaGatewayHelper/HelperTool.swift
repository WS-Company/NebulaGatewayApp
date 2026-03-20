// HelperTool.swift
// NebulaGatewayHelper

import Foundation

/// The privileged helper tool that runs as a LaunchDaemon.
/// Executes Nebula commands with root privileges on behalf of the main app.
final class HelperTool: NSObject, HelperProtocol, NSXPCListenerDelegate, @unchecked Sendable {

    private let version = "1.0.2"

    /// Maps PID → (Process, configPath) for tracking Nebula processes we started.
    private var trackedProcesses: [Int32: (process: Process, configPath: String)] = [:]
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
        guard isValidNebulaBinary(binaryPath) else {
            reply(false, "Invalid Nebula binary path: \(binaryPath)")
            return
        }

        guard FileManager.default.fileExists(atPath: configPath) else {
            reply(false, "Config file not found: \(configPath)")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["-config", configPath]

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
        trackedProcesses[pid] = (process, configPath)
        processLock.unlock()

        // Monitor for unexpected termination — clean up dictionary
        process.terminationHandler = { [weak self] proc in
            let exitPid = proc.processIdentifier
            let exitCode = proc.terminationStatus
            // Write termination info to the nebula log
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                let msg = "\n[NebulaGatewayHelper] Process PID \(exitPid) terminated with exit code \(exitCode)\n"
                handle.write(msg.data(using: .utf8) ?? Data())
                try? handle.close()
            }
            self?.processLock.lock()
            self?.trackedProcesses.removeValue(forKey: exitPid)
            self?.processLock.unlock()
        }

        reply(true, String(pid))
    }

    func stopNebula(pid: Int32, reply: @escaping (Bool, String) -> Void) {
        processLock.lock()
        let tracked = trackedProcesses[pid]
        processLock.unlock()

        if let entry = tracked {
            entry.process.terminate()
            DispatchQueue.global().async {
                var waited: TimeInterval = 0
                while entry.process.isRunning && waited < 5.0 {
                    Thread.sleep(forTimeInterval: 0.1)
                    waited += 0.1
                }
                if entry.process.isRunning {
                    kill(pid, SIGKILL)
                    reply(true, "Force killed PID \(pid)")
                } else {
                    reply(true, "Stopped PID \(pid)")
                }
            }
            return
        }

        // Not tracked — try kill by PID (process started outside helper)
        let result = kill(pid, SIGTERM)
        if result == 0 {
            reply(true, "Sent SIGTERM to PID \(pid)")
        } else {
            let err = String(cString: strerror(errno))
            reply(false, "Failed to kill PID \(pid): \(err)")
        }
    }

    func getRunningProcesses(reply: @escaping ([String: String]) -> Void) {
        // 1. Our tracked processes
        processLock.lock()
        var result: [String: String] = [:]
        var deadPids: [Int32] = []
        for (pid, entry) in trackedProcesses {
            if entry.process.isRunning {
                result[String(pid)] = entry.configPath
            } else {
                deadPids.append(pid)
            }
        }
        for pid in deadPids {
            trackedProcesses.removeValue(forKey: pid)
        }
        processLock.unlock()

        // 2. Scan system via /proc info (non-blocking, no subprocess)
        for entry in findNebulaProcesses() {
            if result[entry.pid] == nil {
                result[entry.pid] = entry.configPath
            }
        }

        reply(result)
    }

    /// Find nebula processes by reading /proc info via sysctl.
    /// Does NOT spawn subprocesses — safe to call from XPC thread.
    private func findNebulaProcesses() -> [(pid: String, configPath: String)] {
        var results: [(pid: String, configPath: String)] = []

        // Get list of all PIDs via sysctl
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: Int = 0

        // First call to get buffer size
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
            return results
        }

        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)

        guard sysctl(&mib, UInt32(mib.count), &procs, &size, nil, 0) == 0 else {
            return results
        }

        let actualCount = size / MemoryLayout<kinfo_proc>.stride

        for i in 0..<actualCount {
            let proc = procs[i]
            let pid = proc.kp_proc.p_pid
            guard pid > 0 else { continue }

            // Get process name
            let comm = proc.kp_proc.p_comm
            let name = withUnsafePointer(to: comm) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) { cStr in
                    String(cString: cStr)
                }
            }

            guard name == "nebula" else { continue }

            // Get full command line args via KERN_PROCARGS2
            var argsMib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
            var argsSize: Int = 0
            guard sysctl(&argsMib, 3, nil, &argsSize, nil, 0) == 0, argsSize > 0 else {
                continue
            }

            var argsBuffer = [UInt8](repeating: 0, count: argsSize)
            guard sysctl(&argsMib, 3, &argsBuffer, &argsSize, nil, 0) == 0 else {
                continue
            }

            // Parse: first 4 bytes = argc, then exec path, then null-separated args
            let args = String(bytes: argsBuffer.dropFirst(4), encoding: .utf8) ?? ""
            let parts = args.split(separator: "\0").map(String.init)

            // Find "-config" argument
            if let configIdx = parts.firstIndex(of: "-config"),
               configIdx + 1 < parts.count {
                let configPath = parts[configIdx + 1]
                results.append((pid: String(pid), configPath: configPath))
            }
        }

        return results
    }

    func ping(reply: @escaping (String) -> Void) {
        reply(version)
    }

    // MARK: - Private

    private func isValidNebulaBinary(_ path: String) -> Bool {
        let fileName = (path as NSString).lastPathComponent
        return fileName == "nebula" && FileManager.default.isExecutableFile(atPath: path)
    }

    private func createLogHandle(at path: String) -> FileHandle? {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }

        guard let handle = FileHandle(forWritingAtPath: path) else { return nil }
        handle.seekToEndOfFile()
        return handle
    }

    /// Scan system for running nebula processes (non-blocking, called from background).
    private func scanSystemNebulaProcesses() -> [String: String]? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-eo", "pid,args"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }

        guard let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else {
            return nil
        }

        var found: [String: String] = [:]
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("/nebula") && trimmed.contains("-config") else { continue }
            guard !trimmed.contains("grep") && !trimmed.contains("helper") else { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let pidStr = String(parts[0]).trimmingCharacters(in: .whitespaces)
            guard Int32(pidStr) != nil else { continue }

            let args = String(parts[1])
            if let range = args.range(of: "-config ") {
                var configPath = String(args[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if let spaceIdx = configPath.firstIndex(of: " ") {
                    configPath = String(configPath[..<spaceIdx])
                }
                if !configPath.isEmpty {
                    found[pidStr] = configPath
                }
            }
        }

        return found.isEmpty ? nil : found
    }
}
