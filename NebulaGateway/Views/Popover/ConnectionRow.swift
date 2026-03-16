// ConnectionRow.swift
// NebulaGateway

import SwiftUI

/// Single connection entry in the popover with status, speed, and action buttons.
struct ConnectionRow: View {

    @Environment(AppState.self) private var appState

    let connection: ConnectionConfig
    let state: ConnectionState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Name with status indicator and IP
            HStack(spacing: 6) {
                StatusBadge(isConnected: state.isRunning)
                Text(connection.name)
                    .fontWeight(.medium)
                if state.isRunning, let ip = state.nebulaIP {
                    Text(ip)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
            }

            // Buttons left, speed right (connected) / status text (disconnected)
            HStack {
                if state.isRunning {
                    ActionButton(
                        String(localized: "popover.connection.stop"),
                        systemImage: "stop.fill",
                        role: .destructive
                    ) {
                        appState.stopConnection(connection.id)
                    }

                    ActionButton(
                        String(localized: "popover.connection.restart"),
                        systemImage: "arrow.clockwise"
                    ) {
                        appState.restartConnection(connection.id)
                    }

                    Spacer()

                    SpeedLabel(
                        speedIn: state.formattedSpeedIn,
                        speedOut: state.formattedSpeedOut
                    )
                } else {
                    ActionButton(
                        String(localized: "popover.connection.start"),
                        systemImage: "play.fill"
                    ) {
                        appState.startConnection(connection.id)
                    }
                    .disabled(!appState.helperManager.status.isReady)

                    Spacer()

                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusText: String {
        switch state.status {
        case .disconnected:   return String(localized: "popover.connection.notConnected")
        case .connecting:     return String(localized: "popover.connection.connecting")
        case .disconnecting:  return String(localized: "popover.connection.disconnecting")
        case .error(let msg): return msg
        case .connected:      return ""  // Handled above
        }
    }
}
