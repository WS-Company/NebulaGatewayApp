// StatusBadge.swift
// NebulaGateway

import SwiftUI

/// Small colored circle indicating connection status.
struct StatusBadge: View {
    let isConnected: Bool

    var body: some View {
        Circle()
            .fill(isConnected ? .green : .secondary.opacity(0.4))
            .frame(width: 8, height: 8)
    }
}
