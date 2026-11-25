// HelperTool.swift
// NebulaGatewayHelper

import CryptoKit
import Foundation

/// The privileged helper tool that runs as a LaunchDaemon.
/// Starts and stops Nebula with root privileges on behalf of the main app, and only for it.
final class HelperTool: NSObject, HelperProtocol, NSXPCListenerDelegate, @unchecked Sendable {

    private let version = "1.2.0"

    /// Only our signed app may connect: its bundle id and our team.
    private static let clientRequirement =
        "anchor apple generic and identifier \"com.nebulagateway.app\" and certificate leaf[subject.OU] = \"5X73B47284\""

    /// Root-owned copy of the bundled nebula; the only binary the helper runs.
    private static let supportDir = "/Library/Application Support/NebulaGateway"
    private static let binDir = supportDir + "/bin"
    private static let binaryPath = binDir + "/nebula"
    private static let logDir = "/Library/Logs/NebulaGateway"

    private static let maxConfigSize = 1 << 20
    private static let maxBinarySize = 256 << 20

    /// Maps PID → (Process, the run copy of its config) for tracking Nebula processes we started.
    private var trackedProcesses: [Int32: (process: Process, runConfig: String)] = [:]
    private let processLock = NSLock()
    private let installLock = NSLock()
    /// Serializes starts, so two callers can't both find a connection free and start it twice.
    private let startLock = NSLock()

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
        guard RunPath.isValidConnectionId(connectionId) else {
            reply(false, "Invalid connection id: \(connectionId)")
            return
        }

        // Only `<the caller's local storage>/<connectionId>/config.yml`, by its canonical path.
        guard let uid = NSXPCConnection.current()?.effectiveUserIdentifier,
              let storage = Self.storageDirectory(of: uid),
              configPath == RunPath.userConfig(storage: storage, connectionId: connectionId)
        else {
            reply(false, "The config must be in the app's local storage. Use \"Move to local storage\" first.")
            return
        }

        startLock.lock()
        defer { startLock.unlock() }

        guard !RunPath.isRunning(
            runConfig: RunPath.config(uid: uid, connectionId: connectionId),
            userConfig: configPath,
            among: runningConfigPaths()
        ) else {
            reply(false, "This connection is already running")
            return
        }

        do {
            try installBinary()
        } catch {
            reply(false, "Nebula binary: \(error.localizedDescription)")
            return
        }

        // Nebula gets a root-owned copy: the user's file can't be swapped under it after the check.
        let runConfig: String
        do {
            runConfig = try Self.copyConfig(from: configPath, uid: uid, connectionId: connectionId)
        } catch {
            reply(false, "Config: \(error.localizedDescription)")
            return
        }

        let logPath = Self.logDir + "/\(connectionId).log"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.binaryPath)
        process.arguments = ["-config", runConfig]

        if let logFileHandle = Self.openLog(at: logPath) {
            process.standardOutput = logFileHandle
            process.standardError = logFileHandle
        }

        // Monitor for unexpected termination — clean up dictionary. Set before the start: a nebula that
        // exits at once must still leave its line in the log.
        process.terminationHandler = { [weak self] proc in
            let exitPid = proc.processIdentifier
            let exitCode = proc.terminationStatus
            // Write termination info to the nebula log
            if let handle = Self.openLog(at: logPath) {
                let msg = "\n[NebulaGatewayHelper] Process PID \(exitPid) terminated with exit code \(exitCode)\n"
                try? handle.write(contentsOf: Data(msg.utf8))
                try? handle.close()
            }
            self?.processLock.lock()
            self?.trackedProcesses.removeValue(forKey: exitPid)
            self?.processLock.unlock()
        }

        do {
            try process.run()
        } catch {
            reply(false, "Failed to start: \(error.localizedDescription)")
            return
        }

        let pid = process.processIdentifier

        // An entry of a process that has already exited is swept by the next getRunningProcesses.
        processLock.lock()
        trackedProcesses[pid] = (process, runConfig)
        processLock.unlock()

        reply(true, String(pid))
    }

    func stopNebula(pid: Int32, reply: @escaping (Bool, String) -> Void) {
        guard pid > 0 else {
            reply(false, "Invalid PID \(pid)")
            return
        }

        guard let uid = NSXPCConnection.current()?.effectiveUserIdentifier else {
            reply(false, "Unknown caller")
            return
        }

        processLock.lock()
        let tracked = trackedProcesses[pid]
        processLock.unlock()

        // The run copy's path names the user who started the process.
        guard RunPath.mayStop(configPath: tracked?.runConfig ?? Self.configPath(of: pid), callerUid: uid) else {
            reply(false, "PID \(pid) was started by another user")
            return
        }

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
        guard let uid = NSXPCConnection.current()?.effectiveUserIdentifier else {
            reply([:])
            return
        }
        let storage = Self.storageDirectory(of: uid)

        let started = runningProcesses()

        // The caller sees its own connections under the path of its own config, and no other user's.
        var result: [String: String] = [:]
        for (pid, path) in started {
            result[pid] = RunPath.reported(configPath: path, callerUid: uid, callerStorage: storage)
        }

        reply(result)
    }

    /// Every running nebula the helper knows of, PID → the config it was started with (a run copy for our own).
    private func runningProcesses() -> [String: String] {
        // 1. Our tracked processes
        processLock.lock()
        var started: [String: String] = [:]
        var deadPids: [Int32] = []
        for (pid, entry) in trackedProcesses {
            if entry.process.isRunning {
                started[String(pid)] = entry.runConfig
            } else {
                deadPids.append(pid)
            }
        }
        for pid in deadPids {
            trackedProcesses.removeValue(forKey: pid)
        }
        processLock.unlock()

        // 2. Scan system via /proc info (non-blocking, no subprocess)
        for entry in findNebulaProcesses() where started[entry.pid] == nil {
            started[entry.pid] = entry.configPath
        }
        return started
    }

    private func runningConfigPaths() -> [String] {
        Array(runningProcesses().values)
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

            // Nebula needs root for its tun device. A user's own process that merely carries the name and a
            // `-config` argument must not show up as anybody's connection.
            guard name == "nebula", proc.kp_eproc.e_ucred.cr_uid == 0 else { continue }

            if let configPath = Self.configPath(of: pid) {
                results.append((pid: String(pid), configPath: configPath))
            }
        }

        return results
    }

    func ping(reply: @escaping (String) -> Void) {
        reply(version)
    }

    // MARK: - Private

    /// The `-config` argument of a process, read via KERN_PROCARGS2 (no subprocess).
    private static func configPath(of pid: Int32) -> String? {
        var argsMib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var argsSize: Int = 0
        guard sysctl(&argsMib, 3, nil, &argsSize, nil, 0) == 0, argsSize > 0 else { return nil }

        var argsBuffer = [UInt8](repeating: 0, count: argsSize)
        guard sysctl(&argsMib, 3, &argsBuffer, &argsSize, nil, 0) == 0 else { return nil }

        // Parse: first 4 bytes = argc, then exec path, then null-separated args
        let args = String(bytes: argsBuffer.dropFirst(4), encoding: .utf8) ?? ""
        let parts = args.split(separator: "\0").map(String.init)

        guard let configIdx = parts.firstIndex(of: "-config"), configIdx + 1 < parts.count else { return nil }
        return parts[configIdx + 1]
    }

    /// The canonical path of a user's local storage (`…/Nebula Gateway/connections`), if it exists.
    private static func storageDirectory(of uid: uid_t) -> String? {
        guard let home = homeDirectory(of: uid) else { return nil }
        return realPath(home + "/Library/Application Support/Nebula Gateway/connections")
    }

    /// Copies the user's config into the root-only run directory and returns the copy's path.
    private static func copyConfig(from path: String, uid: uid_t, connectionId: String) throws -> String {
        let data = try readRegularFile(path, maxSize: maxConfigSize, owner: uid)

        try ensureRootDirectory(supportDir)
        try ensureRootDirectory(RunPath.root, mode: 0o700)
        try ensureRootDirectory(RunPath.userDirectory(uid: uid), mode: 0o700)
        try ensureRootDirectory(RunPath.directory(uid: uid, connectionId: connectionId), mode: 0o700)

        let runConfig = RunPath.config(uid: uid, connectionId: connectionId)
        try writeRootFile(data, to: runConfig, mode: 0o600)
        return runConfig
    }

    /// Reads a file without following a symlink at its last component. It must be a regular file,
    /// of the given owner if one is named, and no larger than `maxSize`.
    private static func readRegularFile(_ path: String, maxSize: Int, owner: uid_t? = nil) throws -> Data {
        // O_NONBLOCK: a FIFO in place of the file must not hang the helper before fstat refuses it.
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else {
            throw HelperError("cannot open \(path): \(String(cString: strerror(errno)))")
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)

        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw HelperError("\(path) is not a regular file")
        }
        if let owner, info.st_uid != owner {
            throw HelperError("\(path) is not owned by the user")
        }
        guard info.st_size <= maxSize else {
            throw HelperError("\(path) is too large")
        }

        var data = Data()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= maxSize else {
                throw HelperError("\(path) is too large")
            }
        }
        return data
    }

    /// Writes a root-owned file through a new temp file in the same directory, then renames it into place,
    /// so a symlink planted at either name is never followed and a running nebula keeps its old file.
    private static func writeRootFile(_ data: Data, to path: String, mode: mode_t) throws {
        let temp = (path as NSString).deletingLastPathComponent + "/.tmp-\(UUID().uuidString)"
        let fd = open(temp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode)
        guard fd >= 0 else {
            throw HelperError("cannot create \(temp): \(String(cString: strerror(errno)))")
        }

        do {
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            try handle.write(contentsOf: data)
            guard fchown(fd, 0, 0) == 0, fchmod(fd, mode) == 0 else {
                throw HelperError("cannot set owner of \(temp): \(String(cString: strerror(errno)))")
            }
            try handle.close()
            guard rename(temp, path) == 0 else {
                throw HelperError("cannot replace \(path): \(String(cString: strerror(errno)))")
            }
        } catch {
            unlink(temp)
            throw error
        }
    }

    private static func isRootRegularFile(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG && info.st_uid == 0
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

        if Self.isRootRegularFile(Self.binaryPath),
           Self.sha256(ofFile: Self.binaryPath) == BundledNebula.sha256 {
            return
        }

        guard let source = Self.bundledBinaryPath() else {
            throw HelperError("cannot locate the app bundle")
        }

        // The bytes that were hashed are the bytes that get installed: the source is read once, by descriptor.
        let data = try Self.readRegularFile(source, maxSize: Self.maxBinarySize)
        guard Self.sha256(of: data) == BundledNebula.sha256 else {
            throw HelperError("the bundled nebula does not match the expected sha256")
        }
        try Self.writeRootFile(data, to: Self.binaryPath, mode: 0o755)
    }

    /// Creates the directory if needed and makes sure it is a real directory owned by root with that mode.
    private static func ensureRootDirectory(_ path: String, mode: mode_t = 0o755) throws {
        if mkdir(path, mode) != 0 && errno != EEXIST {
            throw HelperError("cannot create \(path): \(String(cString: strerror(errno)))")
        }
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else {
            throw HelperError("\(path) is not a directory")
        }
        guard chown(path, 0, 0) == 0, chmod(path, mode) == 0 else {
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

    private static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct HelperError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}
