// HelperManager.swift
// NebulaGateway

import Foundation
import ServiceManagement

/// Manages the privileged helper daemon lifecycle and XPC communication.
@MainActor @Observable
final class HelperManager {

    private(set) var status: HelperStatus = .checking

    private var xpcConnection: NSXPCConnection?
    private var xpcConnectionValid = false
    /// Bumped on every new connection, so a late handler of an old connection can't break the current one.
    private var connectionGeneration = 0
    private let log = AppLogger.shared

    // MARK: - Helper Installation

    /// Register the privileged helper daemon via SMAppService.
    /// Prompts the user for admin credentials on first install.
    func installHelper() {
        let plistName = "\(Constants.helperBundleId).plist"
        let bundlePlistPath = Bundle.main.bundlePath + "/Contents/Library/LaunchDaemons/\(plistName)"

        guard FileManager.default.fileExists(atPath: bundlePlistPath) else {
            let msg = "Helper plist not in app bundle. A signed build is required to install the helper."
            log.warning(msg)
            status = .error(msg)
            return
        }

        let service = SMAppService.daemon(plistName: plistName)

        do {
            try service.register()
            log.info("Privileged helper registered successfully")
            status = .ready
        } catch {
            log.error("Failed to register helper: \(error.localizedDescription)")
            status = .error(error.localizedDescription)
        }
    }

    /// Unregister the privileged helper daemon.
    func uninstallHelper() {
        let service = SMAppService.daemon(plistName: "\(Constants.helperBundleId).plist")

        do {
            try service.unregister()
            log.info("Privileged helper unregistered")
            status = .needsSetup
        } catch {
            log.error("Failed to unregister helper: \(error.localizedDescription)")
        }

        disconnectXPC()
    }

    /// Check if the helper is installed and responding.
    func checkStatus() {
        status = .checking

        // SMAppService requires the launchd plist to be embedded in the signed app bundle
        // at Contents/Library/LaunchDaemons/. During development (unsigned/ad-hoc builds),
        // reading the plist will fail — we fall back to .needsSetup gracefully.
        let plistName = "\(Constants.helperBundleId).plist"
        let bundlePlistPath = Bundle.main.bundlePath + "/Contents/Library/LaunchDaemons/\(plistName)"

        guard FileManager.default.fileExists(atPath: bundlePlistPath) else {
            log.info("Helper plist not found in app bundle (expected in dev builds)")
            status = .needsSetup
            return
        }

        let service = SMAppService.daemon(plistName: plistName)

        switch service.status {
        case .enabled:
            ping { [weak self] version in
                DispatchQueue.main.async {
                    switch version {
                    case nil:
                        self?.status = .error("Helper not responding")
                    case Constants.helperVersion:
                        self?.status = .ready
                    case let other?:
                        self?.log.warning("Helper \(other) is running, the app needs \(Constants.helperVersion)")
                        self?.status = .error(
                            "Helper \(other) is outdated. Restart it: sudo pkill -x \(Constants.helperBundleId)"
                        )
                    }
                }
            }
        case .notRegistered, .notFound:
            status = .needsSetup
        case .requiresApproval:
            status = .error("Helper requires approval in System Settings → Login Items")
        @unknown default:
            status = .needsSetup
        }
    }

    // MARK: - XPC Communication

    /// Get a proxy to the helper for executing commands.
    /// Returns nil if connection fails.
    ///
    /// XPC calls the error, interruption and invalidation handlers on its own background queue. A closure
    /// written here would be inferred as @MainActor, and Swift 6 checks that at runtime: the app trapped
    /// (SIGTRAP) at launch on a Mac without the helper installed. So the handlers are @Sendable and hop
    /// to the main actor explicitly.
    func getHelperProxy() -> HelperProtocol? {
        if let existing = xpcConnection, xpcConnectionValid {
            return existing.remoteObjectProxyWithErrorHandler(
                proxyErrorHandler(generation: connectionGeneration)
            ) as? HelperProtocol
        }

        // Create new connection (or reconnect after invalidation)
        xpcConnection?.invalidate()
        connectionGeneration += 1
        let generation = connectionGeneration

        let conn = NSXPCConnection(machServiceName: Constants.helperBundleId, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        conn.interruptionHandler = { @Sendable [weak self] in
            AppLogger.shared.warning("XPC connection interrupted — will reconnect")
            Task { @MainActor in self?.connectionFailed(generation: generation, drop: false) }
        }
        conn.invalidationHandler = { @Sendable [weak self] in
            AppLogger.shared.warning("XPC connection invalidated — will reconnect")
            Task { @MainActor in self?.connectionFailed(generation: generation, drop: true) }
        }
        conn.resume()

        xpcConnection = conn
        xpcConnectionValid = true
        log.info("XPC connection established to helper")

        return conn.remoteObjectProxyWithErrorHandler(proxyErrorHandler(generation: generation)) as? HelperProtocol
    }

    private func proxyErrorHandler(generation: Int) -> @Sendable (any Error) -> Void {
        { @Sendable [weak self] error in
            AppLogger.shared.error("XPC proxy error: \(error.localizedDescription)")
            Task { @MainActor in self?.connectionFailed(generation: generation, drop: false) }
        }
    }

    /// Marks the connection broken so the next call reconnects. Ignores reports from an older connection.
    private func connectionFailed(generation: Int, drop: Bool) {
        guard generation == connectionGeneration else { return }
        xpcConnectionValid = false
        if drop { xpcConnection = nil }
    }

    // MARK: - Private

    private func disconnectXPC() {
        xpcConnection?.invalidate()
        xpcConnection = nil
    }

    /// Replies with the helper version, or nil if it does not answer.
    private func ping(reply: @escaping (String?) -> Void) {
        guard let helper = getHelperProxy() else {
            reply(nil)
            return
        }
        helper.ping { version in
            reply(version.isEmpty ? nil : version)
        }
    }
}
