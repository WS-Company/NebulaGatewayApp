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
    private var pollStateUpdate: (([String: ConnectionState]) -> Void)?

    init(helperManager: HelperManager) {
        self.helperManager = helperManager
        self.nebulaBinary = binaryLocator.locate()
    }

    // MARK: - Polling

    func startPolling(stateUpdate: @escaping ([String: ConnectionState]) -> Void) {
        stopPolling()
        // Kept here, not captured by the timer: the timer block is @Sendable, and sending a non-Sendable
        // closure from it to the main actor is an error since Xcode 27.
        pollStateUpdate = stateUpdate
        pollRunningProcesses(stateUpdate: stateUpdate)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let stateUpdate = self.pollStateUpdate else { return }
                self.pollRunningProcesses(stateUpdate: stateUpdate)
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        pollStateUpdate = nil
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

    /// Start a Nebula connection. Returns an error message, or nil once the request is sent to the helper.
    /// A refusal from the helper arrives later, through `onFailure` on the main queue.
    func start(connection: ConnectionConfig, onFailure: @escaping (String) -> Void) -> String? {
        guard nebulaBinary != nil else {
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

        log.info("Requesting helper to start '\(connection.name)' with config \(connection.configURL.path)")

        helper.startNebula(
            connectionId: connection.id,
            configPath: connection.configURL.path
        ) { [weak self] success, message in
            if success {
                self?.log.info("Started '\(connection.name)' with PID \(message)")
            } else {
                self?.log.error("Helper failed to start '\(connection.name)': \(message)")
                DispatchQueue.main.async { onFailure(message) }
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
    func restart(connection: ConnectionConfig, pid: Int32, onFailure: @escaping (String) -> Void) {
        log.info("Restarting '\(connection.name)' (PID \(pid))")
        stop(pid: pid, connectionName: connection.name)
        startOnceStopped(connection: connection, pid: pid, attempt: 1, onFailure: onFailure)
    }

    /// Starts the connection once the old process is gone: the helper refuses a start while the connection
    /// still runs one, and a nebula may take a few seconds to exit. After ten seconds it starts regardless,
    /// and the helper's answer is shown.
    private func startOnceStopped(
        connection: ConnectionConfig, pid: Int32, attempt: Int, onFailure: @escaping (String) -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            let startNow = {
                if let error = self.start(connection: connection, onFailure: onFailure) {
                    onFailure(error)
                }
            }
            guard attempt < 10, let helper = self.helperManager.getHelperProxy() else {
                startNow()
                return
            }
            helper.getRunningProcesses { processes in
                let stopped = processes[String(pid)] == nil
                DispatchQueue.main.async {
                    if stopped {
                        startNow()
                    } else {
                        self.startOnceStopped(
                            connection: connection, pid: pid, attempt: attempt + 1, onFailure: onFailure
                        )
                    }
                }
            }
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

        return configParser.extractIP(fromCert: certPath, nebulaCert: binary.certPath)
    }
}
