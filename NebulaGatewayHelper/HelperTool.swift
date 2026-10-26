// HelperTool.swift
// NebulaGatewayHelper

import CryptoKit
import Foundation

/// The privileged helper tool that runs as a LaunchDaemon.
/// Starts and stops Nebula with root privileges on behalf of the main app, and only for it.
final class HelperTool: NSObject, HelperProtocol, NSXPCListenerDelegate, @unchecked Sendable {

    private let version = "1.1.0"

    /// Only our signed app may connect: its bundle id and our team.
    private static let clientRequirement =
        "anchor apple generic and identifier \"com.nebulagateway.app\" and certificate leaf[subject.OU] = \"ZUQ8Q4D64R\""

    /// Root-owned copy of the bundled nebula; the only binary the helper runs.
    private static let supportDir = "/Library/Application Support/NebulaGateway"
    private static let binDir = supportDir + "/bin"
    private static let binaryPath = binDir + "/nebula"
    private static let logDir = "/Library/Logs/NebulaGateway"

    /// Maps PID → (Process, configPath) for tracking Nebula processes we started.
    private var trackedProcesses: [Int32: (process: Process, configPath: String)] = [:]
    private let processLock = NSLock()
    private let installLock = NSLock()

    // MARK: - NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // The system drops messages from any client that does not meet the requirement.
        connection.setCodeSigningRequirement(Self.clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    // MARK: - HelperProtocol

    func startNebula(
        connectionId: String,
        configPath: String,
        reply: @escaping (Bool, String) -> Void
    ) {
        guard Self.isValidConnectionId(connectionId) else {
            reply(false, "Invalid connection id: \(connectionId)")
            return
        }

        guard let uid = NSXPCConnection.current()?.effectiveUserIdentifier,
              Self.isAllowedConfig(configPath, uid: uid)
        else {
            reply(false, "The config must be in the app's local storage. Use \"Move to local storage\" first.")
            return
        }

        do {
            try installBinary()
        } catch {
            reply(false, "Nebula binary: \(error.localizedDescription)")
            return
        }

        let logPath = Self.logDir + "/\(connectionId).log"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.binaryPath)
        process.arguments = ["-config", configPath]

        if let logFileHandle = Self.openLog(at: logPath) {
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
            if let handle = Self.openLog(at: logPath) {
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
        guard pid > 0 else {
            reply(false, "Invalid PID \(pid)")
            return
        }

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

        // Not tracked: still ours if it runs our copy of nebula (the list is empty after a helper restart).
        guard Self.executablePath(of: pid) == Self.binaryPath else {
            reply(false, "PID \(pid) was not started by Nebula Gateway; stop it from the terminal")
            return
        }

        if kill(pid, SIGTERM) == 0 {
            reply(true, "Sent SIGTERM to PID \(pid)")
        } else {
            let err = String(cString: strerror(errno))
            reply(false, "Failed to stop PID \(pid): \(err)")
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

    /// Connection ids look like `connection_1`; they become the log file name.
    private static func isValidConnectionId(_ id: String) -> Bool {
        id.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil
    }

    /// The config must be a regular file of the calling user, inside that user's local storage,
    /// given by its canonical path (no symlinks, no `..`).
    private static func isAllowedConfig(_ path: String, uid: uid_t) -> Bool {
        guard let home = homeDirectory(of: uid),
              let storage = realPath(home + "/Library/Application Support/Nebula Gateway/connections"),
              realPath(path) == path,
              path.hasPrefix(storage + "/")
        else { return false }

        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG && info.st_uid == uid
    }

    private static func homeDirectory(of uid: uid_t) -> String? {
        var entry = passwd()
        var found: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 4096)
        return buffer.withUnsafeMutableBufferPointer { buf -> String? in
            guard getpwuid_r(uid, &entry, buf.baseAddress, buf.count, &found) == 0,
                  found != nil, let dir = entry.pw_dir
            else { return nil }
            return String(cString: dir)
        }
    }

    private static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func executablePath(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))  // PROC_PIDPATHINFO_MAXSIZE
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    /// The nebula shipped next to the helper: `<App>/Contents/Helpers/nebula`.
    private static func bundledBinaryPath() -> String? {
        guard let helperPath = executablePath(of: getpid()) else { return nil }
        return URL(fileURLWithPath: helperPath)
            .deletingLastPathComponent()  // MacOS
            .deletingLastPathComponent()  // Contents
            .appendingPathComponent("Helpers/nebula")
            .path
    }

    /// Puts the bundled nebula into the root-owned bin dir unless the copy there already matches
    /// `BundledNebula.sha256`. The new copy is checked before it replaces the old one by rename,
    /// so a running nebula keeps its file.
    private func installBinary() throws {
        installLock.lock()
        defer { installLock.unlock() }

        try Self.ensureRootDirectory(Self.supportDir)
        try Self.ensureRootDirectory(Self.binDir)

        if Self.sha256(ofFile: Self.binaryPath) == BundledNebula.sha256 {
            return
        }

        guard let source = Self.bundledBinaryPath() else {
            throw HelperError("cannot locate the app bundle")
        }

        let temp = Self.binDir + "/.nebula-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.copyItem(atPath: source, toPath: temp)
        removexattr(temp, "com.apple.quarantine", XATTR_NOFOLLOW)

        guard Self.sha256(ofFile: temp) == BundledNebula.sha256 else {
            try? fm.removeItem(atPath: temp)
            throw HelperError("the bundled nebula does not match the expected sha256")
        }

        guard chown(temp, 0, 0) == 0, chmod(temp, 0o755) == 0, rename(temp, Self.binaryPath) == 0 else {
            let err = String(cString: strerror(errno))
            try? fm.removeItem(atPath: temp)
            throw HelperError("cannot install nebula: \(err)")
        }
    }

    /// Creates the directory if needed and makes sure it is a real directory owned by root, mode 0755.
    private static func ensureRootDirectory(_ path: String) throws {
        if mkdir(path, 0o755) != 0 && errno != EEXIST {
            throw HelperError("cannot create \(path): \(String(cString: strerror(errno)))")
        }
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else {
            throw HelperError("\(path) is not a directory")
        }
        guard chown(path, 0, 0) == 0, chmod(path, 0o755) == 0 else {
            throw HelperError("cannot set owner of \(path): \(String(cString: strerror(errno)))")
        }
    }

    /// Opens the connection log for appending. Never follows a symlink.
    private static func openLog(at path: String) -> FileHandle? {
        guard (try? ensureRootDirectory(logDir)) != nil else { return nil }
        let fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return nil }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    private static func sha256(ofFile path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private struct HelperError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}
