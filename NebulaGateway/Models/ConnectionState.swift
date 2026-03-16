// ConnectionState.swift
// NebulaGateway

import Foundation

/// Runtime state for a Nebula connection (not persisted).
struct ConnectionState: Equatable {

    enum Status: Equatable {
        case disconnected
        case connecting
        case connected
        case disconnecting
        case error(String)
    }

    var status: Status = .disconnected
    var pid: Int32?
    var interfaceName: String?
    var nebulaIP: String?
    var bytesIn: UInt64 = 0
    var bytesOut: UInt64 = 0
    var speedIn: Double = 0   // bytes per second
    var speedOut: Double = 0  // bytes per second

    var isRunning: Bool {
        switch status {
        case .connected, .connecting:
            return true
        default:
            return false
        }
    }

    /// Formatted upload speed string with auto-scaling units.
    var formattedSpeedIn: String {
        Self.formatSpeed(speedIn)
    }

    /// Formatted download speed string with auto-scaling units.
    var formattedSpeedOut: String {
        Self.formatSpeed(speedOut)
    }

    private static func formatSpeed(_ bytesPerSecond: Double) -> String {
        switch bytesPerSecond {
        case ..<1024:
            return String(format: "%.0f B/s", bytesPerSecond)
        case ..<(1024 * 1024):
            return String(format: "%.1f KB/s", bytesPerSecond / 1024)
        default:
            return String(format: "%.1f MB/s", bytesPerSecond / (1024 * 1024))
        }
    }
}
