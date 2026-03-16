// NebulaService.swift
// NebulaGateway

import Foundation

/// High-level service for starting, stopping, and monitoring Nebula connections.
/// Delegates privileged operations to the helper daemon via HelperManager.
@MainActor @Observable
final class NebulaService {

    private let helperManager: HelperManager
    private let validator = FileValidator()
    private let configParser = NebulaConfigParser()
    private let binaryLocator = NebulaBinaryLocator()
    private let log = AppLogger.shared

    private(set) var nebulaBinary: NebulaBinaryLocator.Result?
    private var pollTimer: Timer?

    init(helperManager: HelperManager) {
        self.helperManager = helperManager
        self.nebulaBinary = binaryLocator.locate()
    }

    // MARK: - Polling

    /// Start periodic polling of helper for running process status.
    func startPolling(stateUpdate: @escaping ([String: ConnectionState]) -> Void) {
        stopPolling()
        // Poll immediately
        pollRunningProcesses(stateUpdate: stateUpdate)
        // Then every 3 seconds
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollRunningProcesses(stateUpdate: stateUpdate)
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Ask the helper which Nebula processes are running, match them to connections.
    private func pollRunningProcesses(stateUpdate: @escaping ([String: ConnectionState]) -> Void) {
        guard let helper = helperManager.getHelperProxy() else { return }

        helper.getRunningProcesses { processes in
            // processes: [pidString: configPath]
            DispatchQueue.main.async {
                stateUpdate(
                    processes.reduce(into: [:]) { result, entry in
                        if let pid = Int32(entry.key) {
                            result[entry.value] = ConnectionState(
                                status: .connected,
                                pid: pid
                            )
                        }
                    }
                )
            }
        }
    }

    // MARK: - Connection Lifecycle

    /// Start a Nebula connection.
    func start(connection: ConnectionConfig) -> String? {
        guard let binary = nebulaBinary else {
            log.error("Nebula binary not found")
            return "Nebula binary not found"
        }

        // Validate before starting
        let errors = validator.validateConnection(connection)
        if !errors.isEmpty {
            let msg = errors.map(\.localizedDescription).joined(separator: "; ")
            log.error("Validation failed for '\(connection.name)': \(msg)")
            return msg
        }

        guard let helper = helperManager.getHelperProxy() else {
            return "Cannot connect to privileged helper"
        }

        let logPath = Constants.Paths.logs
            .appendingPathComponent("\(connection.id).log")
            .path

        // Fire and forget — polling will pick up the new process
        helper.startNebula(
            binaryPath: binary.path,
            configPath: connection.configURL.path,
            logPath: logPath
        ) { [weak self] success, message in
            if success {
                self?.log.info("Started '\(connection.name)' with PID \(message)")
            } else {
                self?.log.error("Failed to start '\(connection.name)': \(message)")
            }
        }

        return nil // no error
    }

    /// Stop a running Nebula connection.
    func stop(pid: Int32, connectionName: String) {
        guard let helper = helperManager.getHelperProxy() else { return }

        helper.stopNebula(pid: pid) { [weak self] success, message in
            if success {
                self?.log.info("Stopped '\(connectionName)' (PID \(pid))")
            } else {
                self?.log.error("Failed to stop '\(connectionName)': \(message)")
            }
        }
    }

    /// Restart a running Nebula connection.
    func restart(connection: ConnectionConfig, pid: Int32) {
        stop(pid: pid, connectionName: connection.name)
        // Give it a moment to clean up, then start
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            _ = self?.start(connection: connection)
        }
    }

    /// Refresh the Nebula binary location.
    func refreshBinary() {
        nebulaBinary = binaryLocator.locate()
    }

    /// Extract Nebula IP from a connection's certificate.
    func extractIP(for connection: ConnectionConfig) -> String? {
        guard let binary = nebulaBinary,
              let parsed = try? configParser.parse(at: connection.configPath),
              let certPath = parsed.certPath
        else { return nil }

        return configParser.extractIP(fromCert: certPath, nebulaBinary: binary.path)
    }
}
