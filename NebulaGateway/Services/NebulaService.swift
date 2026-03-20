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

    func startPolling(stateUpdate: @escaping ([String: ConnectionState]) -> Void) {
        stopPolling()
        pollRunningProcesses(stateUpdate: stateUpdate)
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

    private func pollRunningProcesses(stateUpdate: @escaping ([String: ConnectionState]) -> Void) {
        guard let helper = helperManager.getHelperProxy() else {
            log.warning("Polling: cannot get helper proxy")
            return
        }

        helper.getRunningProcesses { processes in
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

    /// Start a Nebula connection. Returns error message or nil on success.
    func start(connection: ConnectionConfig) -> String? {
        guard let binary = nebulaBinary else {
            let msg = "Nebula binary not found"
            log.error(msg)
            return msg
        }

        let errors = validator.validateConnection(connection)
        if !errors.isEmpty {
            let msg = errors.map(\.localizedDescription).joined(separator: "; ")
            log.error("Validation failed for '\(connection.name)': \(msg)")
            return msg
        }

        guard let helper = helperManager.getHelperProxy() else {
            let msg = "Cannot connect to privileged helper"
            log.error(msg)
            return msg
        }

        let logPath = Constants.Paths.logs
            .appendingPathComponent("\(connection.id).log")
            .path

        log.info("Requesting helper to start '\(connection.name)' with config \(connection.configURL.path)")

        helper.startNebula(
            binaryPath: binary.path,
            configPath: connection.configURL.path,
            logPath: logPath
        ) { [weak self] success, message in
            if success {
                self?.log.info("Started '\(connection.name)' with PID \(message)")
            } else {
                self?.log.error("Helper failed to start '\(connection.name)': \(message)")
            }
        }

        return nil
    }

    /// Stop a running Nebula connection.
    func stop(pid: Int32, connectionName: String) {
        guard let helper = helperManager.getHelperProxy() else {
            log.error("Stop '\(connectionName)': cannot get helper proxy")
            return
        }

        log.info("Requesting helper to stop '\(connectionName)' (PID \(pid))")

        helper.stopNebula(pid: pid) { [weak self] success, message in
            if success {
                self?.log.info("Stopped '\(connectionName)': \(message)")
            } else {
                self?.log.error("Failed to stop '\(connectionName)': \(message)")
            }
        }
    }

    /// Restart a running Nebula connection.
    func restart(connection: ConnectionConfig, pid: Int32) {
        log.info("Restarting '\(connection.name)' (PID \(pid))")
        stop(pid: pid, connectionName: connection.name)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            _ = self?.start(connection: connection)
        }
    }

    func refreshBinary() {
        nebulaBinary = binaryLocator.locate()
    }

    func extractIP(for connection: ConnectionConfig) -> String? {
        guard let binary = nebulaBinary,
              let parsed = try? configParser.parse(at: connection.configPath),
              let certPath = parsed.certPath
        else { return nil }

        return configParser.extractIP(fromCert: certPath, nebulaBinary: binary.path)
    }
}
