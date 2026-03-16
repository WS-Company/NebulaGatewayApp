// SettingsWindow.swift
// NebulaGateway

import SwiftUI

/// Main settings window with two tabs: Configurations and About.
struct SettingsWindow: View {

    var body: some View {
        TabView {
            ConfigurationsTab()
                .tabItem {
                    Label(
                        String(localized: "settings.tabs.configurations"),
                        systemImage: "list.bullet"
                    )
                }

            AboutTab()
                .tabItem {
                    Label(
                        String(localized: "settings.tabs.about"),
                        systemImage: "info.circle"
                    )
                }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
