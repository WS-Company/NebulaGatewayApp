// RunPathTests.swift
// The helper's mapping between its root-owned run copies and the users' own configs.

import XCTest

final class RunPathTests: XCTestCase {

    private let storage = "/Users/a/Library/Application Support/Nebula Gateway/connections"
    private let run = "/Library/Application Support/NebulaGateway/run"

    func testConfigAndParseRoundTrip() {
        let path = RunPath.config(uid: 501, connectionId: "connection_1")
        XCTAssertEqual(path, "\(run)/501/connection_1/config.yml")
        let parsed = RunPath.parse(path)
        XCTAssertEqual(parsed?.uid, 501)
        XCTAssertEqual(parsed?.connectionId, "connection_1")
    }

    func testParseRefusesEverythingElse() {
        for path in [
            "\(storage)/connection_1/config.yml",          // a user's own config
            "\(run)/501/connection_1/other.yml",
            "\(run)/501/connection_1/config.yml/x",
            "\(run)/501/../502/connection_1/config.yml",
            "\(run)/501/a/b/config.yml",
            "\(run)/0501/connection_1/config.yml",         // not how a uid prints
            "\(run)/-1/connection_1/config.yml",
            "\(run)/abc/connection_1/config.yml",
            "\(run)/501//config.yml",
            "\(run)x/501/connection_1/config.yml",
            "",
        ] {
            XCTAssertNil(RunPath.parse(path), path)
        }
    }

    func testConnectionIds() {
        XCTAssertTrue(RunPath.isValidConnectionId("connection_12"))
        for id in ["", ".", "..", "a/b", "a b", "a.yml", "connection_1\n", String(repeating: "a", count: 65)] {
            XCTAssertFalse(RunPath.isValidConnectionId(id), id)
        }
    }

    func testReportedShowsOwnRunCopyAsOwnConfig() {
        XCTAssertEqual(
            RunPath.reported(configPath: "\(run)/501/connection_2/config.yml", callerUid: 501, callerStorage: storage),
            "\(storage)/connection_2/config.yml"
        )
    }

    func testReportedHidesAnotherUsersRunCopy() {
        XCTAssertNil(
            RunPath.reported(configPath: "\(run)/502/connection_2/config.yml", callerUid: 501, callerStorage: storage)
        )
    }

    func testReportedWithoutStorageHidesRunCopy() {
        XCTAssertNil(
            RunPath.reported(configPath: "\(run)/501/connection_2/config.yml", callerUid: 501, callerStorage: nil)
        )
    }

    func testReportedKeepsLegacyAndHandStartedPaths() {
        let legacy = "\(storage)/connection_1/config.yml"
        XCTAssertEqual(RunPath.reported(configPath: legacy, callerUid: 502, callerStorage: nil), legacy)
        XCTAssertEqual(RunPath.reported(configPath: "/etc/nebula/config.yml", callerUid: 501, callerStorage: storage),
                       "/etc/nebula/config.yml")
    }

    func testIsRunning() {
        let runConfig = "\(run)/501/connection_1/config.yml"
        let userConfig = "\(storage)/connection_1/config.yml"
        XCTAssertTrue(RunPath.isRunning(runConfig: runConfig, userConfig: userConfig, among: [runConfig]))
        // Started by an older helper or by hand with the user's own file.
        XCTAssertTrue(RunPath.isRunning(runConfig: runConfig, userConfig: userConfig, among: ["/x", userConfig]))
        XCTAssertFalse(RunPath.isRunning(runConfig: runConfig, userConfig: userConfig, among: []))
        XCTAssertFalse(RunPath.isRunning(
            runConfig: runConfig, userConfig: userConfig,
            among: ["\(run)/502/connection_1/config.yml", "\(run)/501/connection_2/config.yml"]
        ))
    }

    func testMayStop() {
        XCTAssertTrue(RunPath.mayStop(configPath: "\(run)/501/connection_1/config.yml", callerUid: 501))
        XCTAssertFalse(RunPath.mayStop(configPath: "\(run)/502/connection_1/config.yml", callerUid: 501))
        // No run copy: started by an older helper, the owner is unknown.
        XCTAssertTrue(RunPath.mayStop(configPath: "\(storage)/connection_1/config.yml", callerUid: 502))
        XCTAssertTrue(RunPath.mayStop(configPath: nil, callerUid: 501))
    }
}
