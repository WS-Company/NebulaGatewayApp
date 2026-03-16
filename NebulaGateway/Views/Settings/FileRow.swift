// FileRow.swift
// NebulaGateway

import SwiftUI

/// A single row in the file table of the configuration editor.
/// Shows file label, current path, and a Choose button.
struct FileRow: View {

    let label: String
    let path: String
    let isEditable: Bool
    let onChoose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 80, alignment: .leading)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(displayPath)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(path)

            Button(String(localized: "settings.editor.choose")) {
                onChoose()
            }
            .controlSize(.small)
            .disabled(!isEditable)
        }
        .padding(.vertical, 2)
    }

    private var displayPath: String {
        guard !path.isEmpty else { return "—" }
        // Show abbreviated path
        return (path as NSString).abbreviatingWithTildeInPath
    }
}
