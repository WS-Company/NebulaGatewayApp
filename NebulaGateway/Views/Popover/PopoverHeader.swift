// PopoverHeader.swift
// NebulaGateway

import SwiftUI

/// Top row of the popover: app name on the left, Settings and Quit icons on the right.
struct PopoverHeader: View {

    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 6) {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(height: 14)
            Text(String(localized: "popover.title"))
                .font(.headline)

            Spacer()

            Button {
                openWindow(id: "settings")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.plain)
            .help(String(localized: "general.settings"))

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help(String(localized: "general.quit"))
        }
    }
}
