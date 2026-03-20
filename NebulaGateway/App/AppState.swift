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

    /// Cache: connection ID → Nebula IP (extracted once, reused)
    private var cachedIPs: [String: String] = [:]
    /// Cache: Nebula IP → interface name
    private var cachedInterfaces: [String: String] = [:]
    /// Counter for periodic heartbeat log (every 20 polls = ~60s)
    private var pollCount = 0

    // MARK: - Initialization

    func initialize() {
        configStorage.ensureDirectories()

        let config = configStorage.loadConfig()
        connections = config.connections

        for conn in connections {
            connectionStates[conn.id] = ConnectionState()
        }

        helperManager.checkStatus()

        nebulaService.startPolling { [weak self] runningByConfigPath in
            self?.updateFromPoll(runningByConfigPath)
        }

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
        guard let connection = connections.first(where: { $0.id == id }) else {
            log.error("startConnection: connection '\(id)' not found")
            return
        }
        log.info("Starting connection '\(connection.name)'")
        connectionStates[id]?.status = .connecting

        if let error = nebulaService.start(connection: connection) {
            log.error("Start failed for '\(connection.name)': \(error)")
            connectionStates[id]?.status = .error(error)
        }
    }

    func stopConnection(_ id: String) {
        guard let connection = connections.first(where: { $0.id == id }) else {
            log.error("stopConnection: connection '\(id)' not found")
            return
        }
        guard let state = connectionStates[id] else {
            log.error("stopConnection: no state for '\(connection.name)'")
            return
        }
        guard let pid = state.pid else {
            log.error("stopConnection: no PID for '\(connection.name)' (status: \(state.status))")
            return
        }

        log.info("Stopping connection '\(connection.name)' (PID \(pid))")
        connectionStates[id]?.status = .disconnecting
        nebulaService.stop(pid: pid, connectionName: connection.name)
    }

    func restartConnection(_ id: String) {
        guard let connection = connections.first(where: { $0.id == id }) else {
            log.error("restartConnection: connection '\(id)' not found")
            return
        }
        guard let state = connectionStates[id] else {
            log.error("restartConnection: no state for '\(connection.name)'")
            return
        }
        guard let pid = state.pid else {
            log.error("restartConnection: no PID for '\(connection.name)' (status: \(state.status))")
            return
        }

        log.info("Restarting connection '\(connection.name)' (PID \(pid))")
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
        // Invalidate caches for this connection
        cachedIPs.removeValue(forKey: connection.id)
        persistConfig()
    }

    func deleteConnection(_ id: String) {
        if connectionStates[id]?.isRunning == true {
            stopConnection(id)
        }
        configStorage.deleteLocalStorage(for: id)
        connections.removeAll { $0.id == id }
        connectionStates.removeValue(forKey: id)
        cachedIPs.removeValue(forKey: id)
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
        pollCount += 1

        // Heartbeat log every ~60 seconds (20 * 3s)
        if pollCount % 20 == 0 {
            let running = connectionStates.values.filter { $0.isRunning }.count
            log.debug("Polling heartbeat: \(connections.count) connections, \(running) running, \(runningByConfigPath.count) detected")
        }

        for conn in connections {
            let resolvedPath = conn.configURL.path

            if let runningState = runningByConfigPath[resolvedPath] {
                var state = runningState

                // Preserve speed data and cached interface from previous state
                if let existing = connectionStates[conn.id] {
                    state.speedIn = existing.speedIn
                    state.speedOut = existing.speedOut
                    state.bytesIn = existing.bytesIn
                    state.bytesOut = existing.bytesOut
                    state.interfaceName = existing.interfaceName
                    state.nebulaIP = existing.nebulaIP
                }

                // Extract IP once and cache
                if state.nebulaIP == nil {
                    if let cached = cachedIPs[conn.id] {
                        state.nebulaIP = cached
                    } else if let ip = nebulaService.extractIP(for: conn) {
                        state.nebulaIP = ip
                        cachedIPs[conn.id] = ip
                        log.info("Resolved Nebula IP for '\(conn.name)': \(ip)")
                    }
                }

                // Detect interface once and cache
                if state.interfaceName == nil, let ip = state.nebulaIP {
                    if let cached = cachedInterfaces[ip] {
                        state.interfaceName = cached
                    } else if let iface = detectInterface(forIP: ip) {
                        state.interfaceName = iface
                        cachedInterfaces[ip] = iface
                    }
                }

                // Log transition to connected
                if connectionStates[conn.id]?.status != .connected {
                    log.info("Connection '\(conn.name)' is now connected (PID \(state.pid ?? 0))")
                }

                connectionStates[conn.id] = state

            } else {
                // Not running
                let current = connectionStates[conn.id]

                if current?.status == .connecting {
                    // Give it a few poll cycles to start (max ~15 seconds)
                    // After that, mark as disconnected
                    if pollCount % 5 == 0 {
                        log.warning("Connection '\(conn.name)' still in connecting state, resetting")
                        connectionStates[conn.id] = ConnectionState(status: .disconnected)
                    }
                } else if current?.status != .disconnected {
                    log.info("Connection '\(conn.name)' is now disconnected (was \(String(describing: current?.status)))")
                    connectionStates[conn.id] = ConnectionState(status: .disconnected)
                    // Clear interface cache (interface gone)
                    if let ip = current?.nebulaIP {
                        cachedInterfaces.removeValue(forKey: ip)
                    }
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

    /// Find which utun interface carries a given Nebula IP by scanning ifaddrs.
    private func detectInterface(forIP nebulaIP: String) -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = cursor {
            defer { cursor = addr.pointee.ifa_next }
            let name = String(cString: addr.pointee.ifa_name)
            guard name.hasPrefix("utun") || name.hasPrefix("nebula") else { continue }
            guard let sockaddr = addr.pointee.ifa_addr, sockaddr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let ipAddr = sockaddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { ptr in
                String(cString: inet_ntoa(ptr.pointee.sin_addr))
            }

            if ipAddr == nebulaIP {
                log.info("Detected interface \(name) for Nebula IP \(nebulaIP)")
                return name
            }
        }
        return nil
    }
}
