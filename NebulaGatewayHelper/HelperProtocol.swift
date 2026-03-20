// HelperProtocol.swift
// NebulaGatewayHelper
//
// This file is identical to NebulaGateway/XPC/HelperProtocol.swift.
// Both targets must share the same protocol definition.

import Foundation

@objc(HelperProtocol) protocol HelperProtocol {

    func startNebula(
        binaryPath: String,
        configPath: String,
        logPath: String,
        reply: @escaping (_ success: Bool, _ message: String) -> Void
    )

    func stopNebula(
        pid: Int32,
        reply: @escaping (_ success: Bool, _ message: String) -> Void
    )

    func getRunningProcesses(
        reply: @escaping (_ processes: [String: String]) -> Void
    )

    func ping(
        reply: @escaping (_ version: String) -> Void
    )
}
