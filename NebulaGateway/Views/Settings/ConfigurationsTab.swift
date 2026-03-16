// ConfigurationsTab.swift
// NebulaGateway

import SwiftUI

/// Configurations tab in Settings: split view with list on the left and editor on the right.
struct ConfigurationsTab: View {

    @Environment(AppState.self) private var appState
    @State private var selectedId: String?

    var body: some View {
        HSplitView {
            ConfigurationList(selectedId: $selectedId)
                .frame(minWidth: 160, idealWidth: 180, maxWidth: 220)

            Group {
                if let selectedId,
                   appState.connections.contains(where: { $0.id == selectedId }) {
                    ConfigurationEditor(connectionId: selectedId)
                } else {
                    ContentUnavailableView(
                        String(localized: "settings.editor.placeholder"),
                        systemImage: "arrow.left",
                        description: Text("")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: appState.connections.count) {
            if let selectedId, !appState.connections.contains(where: { $0.id == selectedId }) {
                self.selectedId = nil
            }
        }
    }
}
