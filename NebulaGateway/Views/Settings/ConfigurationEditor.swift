// ConfigurationEditor.swift
// NebulaGateway

import SwiftUI

/// Right panel of the Configurations tab for editing a selected connection.
struct ConfigurationEditor: View {

    @Environment(AppState.self) private var appState

    let connectionId: String

    @State private var name = ""
    @State private var configPath = ""
    @State private var caPath = ""
    @State private var certPath = ""
    @State private var keyPath = ""
    @State private var isLocalStorage = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    private let parser = NebulaConfigParser()
    private let log = AppLogger.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Name field
            LabeledContent(String(localized: "settings.editor.name")) {
                TextField("", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            // File table
            GroupBox {
                VStack(spacing: 0) {
                    FileRow(
                        label: "config.yml",
                        path: configPath,
                        isEditable: isLocalStorage || configPath.isEmpty
                    ) {
                        chooseFile(
                            title: "Select Nebula config.yml",
                            types: ["yml", "yaml"]
                        ) { url in
                            handleConfigChosen(url)
                        }
                    }
                    Divider()
                    FileRow(label: "CA cert", path: caPath, isEditable: isLocalStorage) {
                        chooseFile(title: "Select CA certificate", types: ["crt", "pem"]) { url in
                            handleCertChosen(url, standardName: Constants.NebulaFiles.caCert, binding: &caPath)
                        }
                    }
                    Divider()
                    FileRow(label: "Node cert", path: certPath, isEditable: isLocalStorage) {
                        chooseFile(title: "Select node certificate", types: ["crt", "pem"]) { url in
                            handleCertChosen(url, standardName: Constants.NebulaFiles.nodeCert, binding: &certPath)
                        }
                    }
                    Divider()
                    FileRow(label: "Key", path: keyPath, isEditable: isLocalStorage) {
                        chooseFile(title: "Select private key", types: ["key", "pem"]) { url in
                            handleCertChosen(url, standardName: Constants.NebulaFiles.nodeKey, binding: &keyPath)
                        }
                    }
                }
            }

            // Move to local storage
            if !isLocalStorage && !configPath.isEmpty {
                let isRunning = appState.connectionStates[connectionId]?.isRunning ?? false
                Button {
                    moveToLocal()
                } label: {
                    Label(
                        String(localized: "settings.editor.moveToLocal"),
                        systemImage: "square.and.arrow.down"
                    )
                }
                .disabled(isRunning)
                .help(isRunning ? "Stop the connection before moving to local storage" : "")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            // Bottom actions
            Divider()
            HStack {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label(
                        String(localized: "settings.editor.delete"),
                        systemImage: "trash"
                    )
                }
                .alert(
                    String(localized: "settings.editor.deleteConfirm"),
                    isPresented: $showDeleteConfirm
                ) {
                    Button(String(localized: "settings.editor.delete"), role: .destructive) {
                        appState.deleteConnection(connectionId)
                    }
                    Button(String(localized: "general.cancel"), role: .cancel) {}
                }

                Spacer()

                Button(String(localized: "settings.editor.save")) {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .onAppear { loadConnection() }
        .onChange(of: connectionId) { _, _ in loadConnection() }
    }

    // MARK: - Data

    private func loadConnection() {
        guard let conn = appState.connections.first(where: { $0.id == connectionId }) else { return }
        name = conn.name
        configPath = conn.configPath
        isLocalStorage = conn.localStorage
        errorMessage = nil

        // Parse config to get PKI paths
        if !configPath.isEmpty, let parsed = try? parser.parse(at: configPath) {
            caPath = parsed.caPath ?? ""
            certPath = parsed.certPath ?? ""
            keyPath = parsed.keyPath ?? ""
        }
    }

    private func save() {
        guard var conn = appState.connections.first(where: { $0.id == connectionId }) else { return }
        conn.name = name
        conn.configPath = configPath
        conn.localStorage = isLocalStorage
        appState.updateConnection(conn)
        errorMessage = nil
        log.info("Saved connection '\(name)'")
    }

    // MARK: - File Selection

    private func chooseFile(title: String, types: [String], completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowedContentTypes = types.compactMap { .init(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }

    private func handleConfigChosen(_ url: URL) {
        if isLocalStorage {
            // Re-import into local storage
            guard var conn = appState.connections.first(where: { $0.id == connectionId }) else { return }
            do {
                try appState.configStorage.reimportConfig(for: &conn, newConfigPath: url)
                appState.updateConnection(conn)
                loadConnection()
            } catch {
                errorMessage = error.localizedDescription
                log.error("Failed to reimport config: \(error.localizedDescription)")
            }
        } else {
            configPath = url.path

            // Parse PKI paths from the chosen config
            if let parsed = try? parser.parse(at: url.path) {
                caPath = parsed.caPath ?? ""
                certPath = parsed.certPath ?? ""
                keyPath = parsed.keyPath ?? ""
            }
        }
    }

    private func handleCertChosen(_ url: URL, standardName: String, binding: inout String) {
        guard isLocalStorage else { return }
        do {
            try appState.configStorage.replaceLocalFile(
                connectionId: connectionId,
                standardName: standardName,
                from: url
            )
            binding = Constants.Paths.connections
                .appendingPathComponent(connectionId)
                .appendingPathComponent(standardName)
                .path
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Local Storage

    private func moveToLocal() {
        do {
            try appState.moveToLocalStorage(connectionId)
            loadConnection()
        } catch {
            errorMessage = error.localizedDescription
            log.error("Failed to move to local storage: \(error.localizedDescription)")
        }
    }
}
