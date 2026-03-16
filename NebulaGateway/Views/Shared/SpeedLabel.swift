// SpeedLabel.swift
// NebulaGateway

import SwiftUI

/// Displays upload and download speed with arrow indicators.
struct SpeedLabel: View {
    let speedIn: String
    let speedOut: String

    var body: some View {
        HStack(spacing: 8) {
            Label(speedOut, systemImage: "arrow.up")
            Label(speedIn, systemImage: "arrow.down")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
}
