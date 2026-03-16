// ActionButton.swift
// NebulaGateway

import SwiftUI

/// Compact styled button used in the popover for Start/Stop/Restart actions.
struct ActionButton: View {
    let title: String
    let systemImage: String
    let role: ButtonRole?
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.caption)
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
    }
}
