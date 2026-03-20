// HelperProtocol.swift
// NebulaGateway
//
// Shared between the main app and the privileged helper.
// Any changes here must be mirrored in NebulaGatewayHelper/HelperProtocol.swift.

import Foundation

/// XPC protocol for communicating with the privileged helper daemon.
/// The helper runs as root and manages Nebula processes.
@objc(HelperProtocol) protocol HelperProtocol {

    /// Start a Nebula process with the given config file.
    /// - Parameters:
    ///   - binaryPath: Absolute path to the nebula binary.
    ///   - configPath: Absolute path to the Nebula config.yml.
    ///   - logPath: Absolute path for stdout/stderr redirection.
    ///   - reply: Callback with (success, message). Message contains the PID on success or error details on failure.
    func startNebula(
        binaryPath: String,
        configPath: String,
        logPath: String,
        reply: @escaping (_ success: Bool, _ message: String) -> Void
    )

    /// Stop a running Nebula process.
    /// - Parameters:
    ///   - pid: Process ID to terminate.
    ///   - reply: Callback with (success, message).
    func stopNebula(
        pid: Int32,
        reply: @escaping (_ success: Bool, _ message: String) -> Void
    )

    /// Check which Nebula processes are currently running.
    /// - Parameter reply: Dictionary mapping PID (as String) to the config path it was started with.
    func getRunningProcesses(
        reply: @escaping (_ processes: [String: String]) -> Void
    )

    /// Verify the helper is alive and responding.
    /// - Parameter reply: Helper version string.
    func ping(
        reply: @escaping (_ version: String) -> Void
    )
}
