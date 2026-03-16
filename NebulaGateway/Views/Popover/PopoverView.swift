// PopoverView.swift
// NebulaGateway

import SwiftUI

/// Root view for the menu bar popover.
struct PopoverView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader()
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)

            Divider()

            HelperStatusView()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            Divider()

            if appState.connections.isEmpty {
                emptyState
            } else {
                connectionList
            }
        }
        .frame(width: 320)
    }

    // MARK: - Subviews

    private var connectionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(appState.connections.enumerated()), id: \.element.id) { index, connection in
                if index > 0 {
                    Divider().padding(.horizontal, 12)
                }

                let state = appState.connectionStates[connection.id] ?? ConnectionState()
                ConnectionRow(connection: connection, state: state)
                    .padding(.horizontal, 12)
            }

            Divider()

            addButton
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            addButton
        }
        .padding(.vertical, 8)
    }

    private var addButton: some View {
        Button {
            openWindow(id: "settings")
            NSApplication.shared.activate(ignoringOtherApps: true)
        } label: {
            Label(
                String(localized: "popover.addConfiguration"),
                systemImage: "plus"
            )
            .font(.caption)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
    }
}
