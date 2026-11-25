// RestoreTests.swift
// Which connections come back on launch, and that the wanted state survives config.toml.

import XCTest

final class RestoreTests: XCTestCase {

    private func conn(_ n: Int, connected: Bool, local: Bool = true) -> ConnectionConfig {
        ConnectionConfig(
            id: "connection_\(n)", name: "c\(n)", configPath: "/s/connection_\(n)/config.yml",
            localStorage: local, connected: connected
        )
    }

    func testRestoresOnlyWantedLocalAndNotRunning() {
        let connections = [
            conn(1, connected: true),                  // was on, not running → start
            conn(2, connected: false),                 // switched off → stays off
            conn(3, connected: true),                  // still running (the app was only quit) → no second nebula
            conn(4, connected: true, local: false),    // cannot be started outside local storage
        ]
        XCTAssertEqual(
            ConnectionConfig.idsToRestore(connections, runningConfigPaths: ["/s/connection_3/config.yml"]),
            ["connection_1"]
        )
    }

    func testRunningCountsAsWanted() {
        let connections = [conn(1, connected: false), conn(2, connected: false), conn(3, connected: false, local: false)]
        XCTAssertEqual(
            ConnectionConfig.idsRunning(
                connections, runningConfigPaths: ["/s/connection_1/config.yml", "/s/connection_3/config.yml", "/other"]
            ),
            ["connection_1", "connection_3"]
        )
    }

    func testNothingToRestore() {
        XCTAssertEqual(ConnectionConfig.idsToRestore([], runningConfigPaths: []), [])
        XCTAssertEqual(ConnectionConfig.idsToRestore([conn(1, connected: false)], runningConfigPaths: []), [])
    }

    func testConnectedSurvivesConfigToml() throws {
        var config = AppConfiguration()
        config.connections = [conn(1, connected: true), conn(2, connected: false)]
        let decoded = try TOMLDecoder.decode(AppConfiguration.self, from: TOMLEncoder.encode(config))
        XCTAssertEqual(decoded.connections, config.connections)
    }

    func testOldConfigWithoutTheKeyReadsAsOff() throws {
        let old = """
        [app]
        version = "1.0.0"
        first_run = false

        [[connections]]
        id = "connection_1"
        name = "evn"
        config_path = "/s/connection_1/config.yml"
        local_storage = true
        autostart = true
        """
        let decoded = try TOMLDecoder.decode(AppConfiguration.self, from: old)
        XCTAssertEqual(decoded.connections, [conn(1, connected: false)].map {
            var c = $0; c.name = "evn"; return c
        })
    }
}
