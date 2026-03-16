// HelperManager.swift
// NebulaGateway

import Foundation
import ServiceManagement

/// Manages the privileged helper daemon lifecycle and XPC communication.
@MainActor @Observable
final class HelperManager {

    private(set) var status: HelperStatus = .checking

    private var xpcConnection: NSXPCConnection?
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
        let connection: NSXPCConnection
        if let existing = xpcConnection {
            connection = existing
        } else {
            let newConn = NSXPCConnection(machServiceName: Constants.helperBundleId, options: .privileged)
            newConn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
            newConn.resume()
            xpcConnection = newConn
            connection = newConn
        }

        return connection.remoteObjectProxyWithErrorHandler { error in
            AppLogger.shared.error("XPC proxy error: \(error.localizedDescription)")
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
