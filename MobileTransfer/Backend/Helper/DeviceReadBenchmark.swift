#if DEBUG
import Foundation
import AppKit
import ImageIO

/// Read-only USB benchmark. Each invocation starts with empty process memory.
/// Logs timing and success only; never device identifiers, records, or app names.
enum DeviceReadBenchmark {
    static func run() {
        let manager = AppleMobileDeviceManager.shared
        let identifiers = measure("discovery") { manager.listDeviceIdentifiers() }
        let usbCount = identifiers.filter { manager.remoteDeviceHandlerIdentifier(udid: $0, connection: .usb) != nil }.count
        let networkCount = identifiers.filter { manager.remoteDeviceHandlerIdentifier(udid: $0, connection: .net) != nil }.count
        print("DEVICE_BENCH transport_usb=\(usbCount) transport_network=\(networkCount) enumerated=\(identifiers.count)")
        let usbIdentifiers = identifiers.filter { manager.remoteDeviceHandlerIdentifier(udid: $0, connection: .usb) != nil }
        guard usbIdentifiers.count == 1, let udid = usbIdentifiers.first else {
            print("DEVICE_BENCH requires exactly one connected device")
            return
        }
        print("DEVICE_BENCH encryption_native=\(String(describing: manager.readBackupEncryptionStatus(udid: udid)))")
        let start = DispatchTime.now().uptimeNanoseconds
        let record = measure("device_record") { manager.obtainDeviceInfo(udid: udid, connection: .usb) }
        if CommandLine.arguments.contains("--batched") {
            let values = measure("batched_details") {
                manager.readLockdownValues(udid: udid, domains: [
                    "com.apple.mobile.battery", "com.apple.disk_usage", "com.apple.mobile.backup",
                ], connection: .usb)
            }
            print("DEVICE_BENCH optimized_summary_ms=\(milliseconds(since: start)) success=\(record != nil && values.count == 3)")
        } else {
            let battery = measure("battery") { manager.readFromLockdown(udid: udid, domain: "com.apple.mobile.battery", connection: .usb) }
            let storage = measure("storage") { manager.readFromLockdown(udid: udid, domain: "com.apple.disk_usage", connection: .usb) }
            let encryption = measure("encryption") { manager.readFromLockdown(udid: udid, domain: "com.apple.mobile.backup", connection: .usb) }
            print("DEVICE_BENCH baseline_summary_ms=\(milliseconds(since: start)) success=\(record != nil && battery != nil && storage != nil && encryption != nil)")
        }
        if CommandLine.arguments.contains("--verify") {
            let domains = ["com.apple.mobile.battery", "com.apple.disk_usage", "com.apple.mobile.backup"]
            let batch = manager.readLockdownValues(udid: udid, domains: domains + ["tech.nootag.itm.nonexistent"], connection: .usb)
            let valid = domains.allSatisfy { domain in
                guard let expected = manager.readFromLockdown(udid: udid, domain: domain, connection: .usb)?.value as? [String: Any],
                      let actual = batch[domain]?.value as? [String: Any] else { return false }
                let stableKey = domain == "com.apple.disk_usage" ? "TotalDiskCapacity" : domain == "com.apple.mobile.backup" ? "WillEncrypt" : "BatteryCurrentCapacity"
                return String(describing: expected[stableKey]) == String(describing: actual[stableKey])
            }
            // Some iOS versions return an empty dictionary for an unknown domain.
            // Preserve the single-read API's actual behavior rather than assuming nil.
            let singleMissing = manager.readFromLockdown(udid: udid, domain: "tech.nootag.itm.nonexistent", connection: .usb)
            let fallbackValid = batch["tech.nootag.itm.nonexistent"] == singleMissing
            let disconnected = manager.readLockdownValues(udid: "00000000-0000000000000000", domains: domains, connection: .usb).isEmpty
            print("DEVICE_BENCH verification_values=\(valid) unknown_domain_matches=\(fallbackValid) disconnected_empty=\(disconnected)")
            guard valid && fallbackValid && disconnected else { exit(1) }
        }
        let apps = measure("applications") { manager.listApplications(udid: udid, connection: .usb, includeIcons: false) }
        print("DEVICE_BENCH applications_success=\(apps != nil)")
        if CommandLine.arguments.contains("--icons"), let apps {
            let progress = Progress(totalUnitCount: Int64(apps.count))
            var received = 0
            let iconStart = DispatchTime.now().uptimeNanoseconds
            measure("all_icons") {
                manager.readApplicationIcons(udid: udid, identifiers: apps.keys.sorted(), progress: progress) { _, data in
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                          CGImageSourceCreateThumbnailAtIndex(source, 0, [
                              kCGImageSourceThumbnailMaxPixelSize: 64,
                              kCGImageSourceCreateThumbnailFromImageAlways: true,
                              kCGImageSourceCreateThumbnailWithTransform: true,
                              kCGImageSourceShouldCacheImmediately: true,
                          ] as CFDictionary) != nil else { return }
                    received += 1
                    if received == 1 { print("DEVICE_BENCH first_icon_ms=\(milliseconds(since: iconStart))") }
                }
            }
            print("DEVICE_BENCH valid_icons=\(received) app_count=\(apps.count)")
            let cancelled = Progress(totalUnitCount: 1)
            cancelled.cancel()
            var cancelledCallbacks = 0
            manager.readApplicationIcons(udid: udid, identifiers: Array(apps.keys), progress: cancelled) { _, _ in cancelledCallbacks += 1 }
            print("DEVICE_BENCH icon_cancellation=\(cancelledCallbacks == 0)")
            guard received > 0, cancelledCallbacks == 0 else { exit(1) }
        }
    }

    @discardableResult
    static func measure<T>(_ name: String, _ work: () -> T) -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        let result = work()
        print("DEVICE_BENCH \(name)_ms=\(milliseconds(since: start))")
        return result
    }

    static func milliseconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }
}
#endif
