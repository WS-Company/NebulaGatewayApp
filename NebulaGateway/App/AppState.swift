// AppState.swift
// NebulaGateway

import Foundation
import SwiftUI

/// Central observable state for the entire application.
/// Coordinates between services and provides data to views.
@MainActor @Observable
final class AppState {

    // MARK: - Published State

    var connections: [ConnectionConfig] = []
    var connectionStates: [String: ConnectionState] = [:]
    var selectedConnectionId: String?
    var settingsWindowVisible = false

    // MARK: - Services

    let helperManager = HelperManager()
    let configStorage = ConfigStorageService()
    let networkMonitor = NetworkMonitor()

    private var _nebulaService: NebulaService?
    var nebulaService: NebulaService {
        if let existing = _nebulaService { return existing }
        let service = NebulaService(helperManager: helperManager)
        _nebulaService = service
        return service
    }

    private let log = AppLogger.shared

    // MARK: - Initialization

    func initialize() {
        configStorage.ensureDirectories()

        let config = configStorage.loadConfig()
        connections = config.connections

        // Initialize states for all connections
        for conn in connections {
            connectionStates[conn.id] = ConnectionState()
        }

        // Check helper
        helperManager.checkStatus()

        // Start polling for running processes (picks up already-running nebula)
        nebulaService.startPolling { [weak self] runningByConfigPath in
            self?.updateFromPoll(runningByConfigPath)
        }

        // Start network speed monitor
        networkMonitor.start { [weak self] interfaceName, speedIn, speedOut, totalIn, totalOut in
            DispatchQueue.main.async {
                self?.updateSpeed(
                    interface: interfaceName,
                    speedIn: speedIn, speedOut: speedOut,
                    totalIn: totalIn, totalOut: totalOut
                )
            }
        }

        nebulaService.refreshBinary()
        log.info("App initialized with \(connections.count) connection(s)")
    }

    // MARK: - Connection Actions

    func startConnection(_ id: String) {
        guard let connection = connections.first(where: { $0.id == id }) else { return }
        connectionStates[id]?.status = .connecting

        if let error = nebulaService.start(connection: connection) {
            connectionStates[id]?.status = .error(error)
        }
        // Polling will pick up the running state
    }

    func stopConnection(_ id: String) {
        guard let connection = connections.first(where: { $0.id == id }),
              let state = connectionStates[id],
              let pid = state.pid
        else { return }

        connectionStates[id]?.status = .disconnecting
        nebulaService.stop(pid: pid, connectionName: connection.name)
        // Polling will pick up the stopped state
    }

    func restartConnection(_ id: String) {
        guard let connection = connections.first(where: { $0.id == id }),
              let state = connectionStates[id],
              let pid = state.pid
        else { return }

        connectionStates[id]?.status = .connecting
        nebulaService.restart(connection: connection, pid: pid)
    }

    // MARK: - Configuration Management

    func addConnection(name: String, configPath: String) {
        let existingIds = connections.map(\.id)
        let connection = ConnectionConfig.create(name: name, configPath: configPath, existingIds: existingIds)
        connections.append(connection)
        connectionStates[connection.id] = ConnectionState()
        persistConfig()
        log.info("Added connection '\(name)'")
    }

    func updateConnection(_ connection: ConnectionConfig) {
        guard let index = connections.firstIndex(where: { $0.id == connection.id }) else { return }
        connections[index] = connection
        persistConfig()
    }

    func deleteConnection(_ id: String) {
        if connectionStates[id]?.isRunning == true {
            stopConnection(id)
        }
        configStorage.deleteLocalStorage(for: id)
        connections.removeAll { $0.id == id }
        connectionStates.removeValue(forKey: id)
        if selectedConnectionId == id {
            selectedConnectionId = nil
        }
        persistConfig()
        log.info("Deleted connection \(id)")
    }

    func moveToLocalStorage(_ id: String) throws {
        guard var connection = connections.first(where: { $0.id == id }) else { return }
        try configStorage.moveToLocalStorage(&connection)
        updateConnection(connection)
    }

    var hasRunningConnections: Bool {
        connectionStates.values.contains { $0.isRunning }
    }

    // MARK: - Private

    private func persistConfig() {
        var config = AppConfiguration()
        config.app.firstRun = false
        config.connections = connections
        configStorage.saveConfig(config)
    }

    /// Match running processes (by config path) to our connections and update states.
    private func updateFromPoll(_ runningByConfigPath: [String: ConnectionState]) {
        for conn in connections {
            let resolvedPath = conn.configURL.path

            if let runningState = runningByConfigPath[resolvedPath] {
                // This connection's nebula is running
                var state = runningState
                // Preserve speed data from previous state
                if let existing = connectionStates[conn.id] {
                    state.speedIn = existing.speedIn
                    state.speedOut = existing.speedOut
                    state.bytesIn = existing.bytesIn
                    state.bytesOut = existing.bytesOut
                    state.interfaceName = existing.interfaceName
                }
                // Extract IP if not yet known
                if state.nebulaIP == nil {
                    state.nebulaIP = nebulaService.extractIP(for: conn)
                }
                connectionStates[conn.id] = state
            } else {
                // Not running
                let current = connectionStates[conn.id]
                if current?.status == .connecting {
                    // Still starting, don't overwrite yet (give it a few poll cycles)
                } else if current?.status != .disconnected {
                    // Was running/disconnecting/error, now confirmed stopped
                    connectionStates[conn.id] = ConnectionState(status: .disconnected)
                }
            }
        }
    }

    private func updateSpeed(
        interface: String,
        speedIn: Double, speedOut: Double,
        totalIn: UInt64, totalOut: UInt64
    ) {
        for (id, state) in connectionStates {
            if state.interfaceName == interface {
                connectionStates[id]?.speedIn = speedIn
                connectionStates[id]?.speedOut = speedOut
                connectionStates[id]?.bytesIn = totalIn
                connectionStates[id]?.bytesOut = totalOut
            }
        }
    }
}
