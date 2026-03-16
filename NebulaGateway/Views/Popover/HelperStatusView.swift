// HelperStatusView.swift
// NebulaGateway

import SwiftUI

/// Displays the privileged helper daemon status.
/// Collapsed to one line when ready, expanded with description when setup is needed.
struct HelperStatusView: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        let status = appState.helperManager.status

        Group {
            switch status {
            case .ready:
                compactView

            case .needsSetup:
                expandedView

            case .checking:
                HStack {
                    Text(String(localized: "popover.helper.title"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                }

            case .error(let message):
                expandedErrorView(message)
            }
        }
    }

    // MARK: - Subviews

    private var compactView: some View {
        HStack {
            Text(String(localized: "popover.helper.title"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(String(localized: "popover.helper.ready"))
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(localized: "popover.helper.title"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button(String(localized: "popover.helper.setup")) {
                    appState.helperManager.installHelper()
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
            }
            Text(String(localized: "popover.helper.description"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func expandedErrorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(localized: "popover.helper.title"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button(String(localized: "popover.helper.retry")) {
                    appState.helperManager.checkStatus()
                }
                .controlSize(.small)
            }
            Text(message)
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }
}
