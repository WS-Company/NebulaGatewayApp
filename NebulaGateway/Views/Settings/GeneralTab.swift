// GeneralTab.swift
// NebulaGateway

import ServiceManagement
import SwiftUI

/// App-wide switches. The login item's state lives in macOS (SMAppService), not in config.toml.
struct GeneralTab: View {

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var errorMessage: String?

    private let log = AppLogger.shared

    var body: some View {
        Form {
            Toggle(
                String(localized: "settings.general.launchAtLogin"),
                isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin)
            )

            Text(String(localized: "settings.general.launchAtLogin.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)

            if SMAppService.mainApp.status == .requiresApproval {
                Button(String(localized: "settings.general.launchAtLogin.approve")) {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // The user may have changed it in System Settings → Login Items.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
            log.info("Launch at login \(enabled ? "enabled" : "disabled")")
        } catch {
            errorMessage = error.localizedDescription
            log.error("Launch at login: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
