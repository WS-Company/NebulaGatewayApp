// NetworkMonitor.swift
// NebulaGateway

import Foundation
import Darwin

/// Monitors network interface traffic to calculate Nebula connection speed.
/// Reads bytes in/out from the system's interface statistics.
final class NetworkMonitor {

    private var timer: Timer?
    private var previousSamples: [String: Sample] = [:]
    private let log = AppLogger.shared

    private struct Sample {
        let bytesIn: UInt64
        let bytesOut: UInt64
        let timestamp: Date
    }

    typealias SpeedUpdate = (_ interfaceName: String, _ speedIn: Double, _ speedOut: Double, _ totalIn: UInt64, _ totalOut: UInt64) -> Void

    private var onUpdate: SpeedUpdate?

    // MARK: - Public API

    /// Start monitoring the specified interfaces.
    func start(onUpdate: @escaping SpeedUpdate) {
        self.onUpdate = onUpdate
        stop()

        timer = Timer.scheduledTimer(
            withTimeInterval: Constants.Monitoring.speedUpdateInterval,
            repeats: true
        ) { [weak self] _ in
            self?.pollInterfaces()
        }

        // Fire immediately for initial state
        pollInterfaces()
    }

    /// Stop monitoring.
    func stop() {
        timer?.invalidate()
        timer = nil
        previousSamples.removeAll()
    }

    // MARK: - Private

    private func pollInterfaces() {
        let stats = readInterfaceStats()

        for (name, current) in stats {
            let totalIn = current.bytesIn
            let totalOut = current.bytesOut

            var speedIn: Double = 0
            var speedOut: Double = 0

            if let previous = previousSamples[name] {
                let elapsed = current.timestamp.timeIntervalSince(previous.timestamp)
                if elapsed > 0,
                   current.bytesIn >= previous.bytesIn,
                   current.bytesOut >= previous.bytesOut {
                    speedIn = Double(current.bytesIn - previous.bytesIn) / elapsed
                    speedOut = Double(current.bytesOut - previous.bytesOut) / elapsed
                }
                // If counters went backwards (interface reset), skip this sample
            }

            previousSamples[name] = current
            onUpdate?(name, speedIn, speedOut, totalIn, totalOut)
        }
    }

    /// Reads byte counters for all utun/nebula interfaces using getifaddrs.
    private func readInterfaceStats() -> [String: Sample] {
        var stats: [String: Sample] = [:]

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return stats
        }
        defer { freeifaddrs(ifaddr) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = cursor {
            let name = String(cString: addr.pointee.ifa_name)

            // Only monitor utun (macOS) and nebula interfaces
            if name.hasPrefix("utun") || name.hasPrefix("nebula") {
                if addr.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                   let data = addr.pointee.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                    stats[name] = Sample(
                        bytesIn: UInt64(networkData.ifi_ibytes),
                        bytesOut: UInt64(networkData.ifi_obytes),
                        timestamp: Date()
                    )
                }
            }

            cursor = addr.pointee.ifa_next
        }

        return stats
    }
}
