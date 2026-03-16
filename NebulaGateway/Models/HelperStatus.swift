// HelperStatus.swift
// NebulaGateway

import Foundation

/// Represents the current state of the privileged helper daemon.
enum HelperStatus: Equatable {
    /// Checking helper availability (initial state on launch).
    case checking
    /// Helper is installed and responding to XPC calls.
    case ready
    /// Helper is not installed or not responding; user action required.
    case needsSetup
    /// Helper encountered an error.
    case error(String)

    var isReady: Bool {
        self == .ready
    }

    var displayText: String {
        switch self {
        case .checking:    return String(localized: "popover.helper.checking")
        case .ready:       return String(localized: "popover.helper.ready")
        case .needsSetup:  return String(localized: "popover.helper.setup")
        case .error:       return String(localized: "popover.helper.error")
        }
    }
}
