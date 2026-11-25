// RunPath.swift
// NebulaGatewayHelper
//
// Where the helper keeps its root-owned copy of a connection's config, and how that path maps back to the
// user's own file. Pure functions: the unit tests compile this file alone.

import Foundation

enum RunPath {

    static let root = "/Library/Application Support/NebulaGateway/run"
    static let configName = "config.yml"

    /// Connection ids look like `connection_1`; they name the log file and the run directory.
    static func isValidConnectionId(_ id: String) -> Bool {
        // \z, not $: ICU's $ also matches before a final line break.
        id.range(of: "\\A[A-Za-z0-9_-]{1,64}\\z", options: .regularExpression) != nil
    }

    static func userDirectory(uid: uid_t) -> String {
        "\(root)/\(uid)"
    }

    static func directory(uid: uid_t, connectionId: String) -> String {
        "\(userDirectory(uid: uid))/\(connectionId)"
    }

    /// The root-owned copy nebula is started with: `<root>/<uid>/<connectionId>/config.yml`.
    static func config(uid: uid_t, connectionId: String) -> String {
        "\(directory(uid: uid, connectionId: connectionId))/\(configName)"
    }

    /// The user and connection a run config stands for; nil for any other path.
    static func parse(_ path: String) -> (uid: uid_t, connectionId: String)? {
        guard path.hasPrefix(root + "/") else { return nil }
        let parts = path.dropFirst(root.count + 1).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let uid = uid_t(parts[0]), String(uid) == parts[0],
              isValidConnectionId(String(parts[1])),
              parts[2] == configName
        else { return nil }
        return (uid, String(parts[1]))
    }

    /// The user's own config of a connection: `<storage>/<connectionId>/config.yml`.
    static func userConfig(storage: String, connectionId: String) -> String {
        "\(storage)/\(connectionId)/\(configName)"
    }

    /// What a caller is told about a nebula started with `configPath`: its own run copies as the path of
    /// its own config, another user's run copies not at all, anything else (started by an older helper or by
    /// hand) as is.
    static func reported(configPath: String, callerUid: uid_t, callerStorage: String?) -> String? {
        guard let owner = parse(configPath) else { return configPath }
        guard owner.uid == callerUid, let storage = callerStorage else { return nil }
        return userConfig(storage: storage, connectionId: owner.connectionId)
    }

    /// Whether a connection already has a nebula: one started with its run copy, or with the user's own config
    /// (by a helper older than 1.2.0, or by hand). A second one would fight the first for the same address.
    static func isRunning(runConfig: String, userConfig: String, among runningConfigPaths: [String]) -> Bool {
        runningConfigPaths.contains { $0 == runConfig || $0 == userConfig }
    }

    /// Whether the caller may stop a nebula started with `configPath`. A process without a run copy has no
    /// known owner and stays allowed.
    static func mayStop(configPath: String?, callerUid: uid_t) -> Bool {
        guard let configPath, let owner = parse(configPath) else { return true }
        return owner.uid == callerUid
    }
}
