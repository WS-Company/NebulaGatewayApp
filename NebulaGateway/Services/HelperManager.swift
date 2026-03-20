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
            ping { [weak self] success in
                DispatchQueue.main.async {
                    self?.status = success ? .ready : .error("Helper not responding")
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
    func getHelperProxy() -> HelperProtocol? {
        if let existing = xpcConnection, xpcConnectionValid {
            return existing.remoteObjectProxyWithErrorHandler { [weak self] error in
                AppLogger.shared.error("XPC proxy error: \(error.localizedDescription)")
                self?.xpcConnectionValid = false
            } as? HelperProtocol
        }

        // Create new connection (or reconnect after invalidation)
        xpcConnection?.invalidate()

        let conn = NSXPCConnection(machServiceName: Constants.helperBundleId, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        conn.interruptionHandler = { [weak self] in
            AppLogger.shared.warning("XPC connection interrupted — will reconnect")
            self?.xpcConnectionValid = false
        }
        conn.invalidationHandler = { [weak self] in
            AppLogger.shared.warning("XPC connection invalidated — will reconnect")
            self?.xpcConnectionValid = false
            self?.xpcConnection = nil
        }
        conn.resume()

        xpcConnection = conn
        xpcConnectionValid = true
        log.info("XPC connection established to helper")

        return conn.remoteObjectProxyWithErrorHandler { [weak self] error in
            AppLogger.shared.error("XPC proxy error: \(error.localizedDescription)")
            self?.xpcConnectionValid = false
        } as? HelperProtocol
    }

    // MARK: - Private

    private func disconnectXPC() {
        xpcConnection?.invalidate()
        xpcConnection = nil
    }

    private func ping(reply: @escaping (Bool) -> Void) {
        guard let helper = getHelperProxy() else {
            reply(false)
            return
        }
        helper.ping { version in
            reply(!version.isEmpty)
        }
    }
}
