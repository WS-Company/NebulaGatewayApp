// NebulaGatewayApp.swift
// NebulaGateway

import SwiftUI

@main
struct NebulaGatewayApp: App {

    @State private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(appState)
        } label: {
            Image(appState.hasRunningConnections ? "MenuBarIconActive" : "MenuBarIconInactive")
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsWindow()
                .environment(appState)
                .onAppear {
                    // Show Dock icon when Settings window opens
                    NSApplication.shared.setActivationPolicy(.regular)
                }
                .onDisappear {
                    // Hide Dock icon when Settings window closes
                    NSApplication.shared.setActivationPolicy(.accessory)
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 700, height: 480)
    }

    init() {
        appState.initialize()
        // Hide from Dock on launch
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
