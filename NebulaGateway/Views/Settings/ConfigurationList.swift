// ConfigurationList.swift
// NebulaGateway

import SwiftUI

/// Left panel of the Configurations tab showing all connections.
struct ConfigurationList: View {

    @Environment(AppState.self) private var appState
    @Binding var selectedId: String?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedId) {
                ForEach(appState.connections) { connection in
                    HStack {
                        Text(connection.name)
                            .lineLimit(1)
                        Spacer()
                        StatusBadge(
                            isConnected: appState.connectionStates[connection.id]?.isRunning ?? false
                        )
                    }
                    .tag(connection.id)
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.sidebar)

            Divider()

            Button {
                addNewConnection()
            } label: {
                Label(
                    String(localized: "settings.editor.add"),
                    systemImage: "plus"
                )
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(8)
        }
    }

    private func addNewConnection() {
        let name = "Connection \(appState.connections.count + 1)"
        appState.addConnection(name: name, configPath: "")
        if let newConn = appState.connections.last {
            selectedId = newConn.id
        }
    }
}
