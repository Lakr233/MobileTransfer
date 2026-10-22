import Foundation

/// Keeps transport values intact while presenting names, units and status text.
/// Unknown internal fields are not guessed or exposed as user-facing information.
enum DeviceInformationPresentation {
    struct Row: Identifiable {
        let id: String
        let title: String
        let value: String
        let detail: String
    }
    private enum Kind {
        case text, bytes, percent, charging, externalPower, supported, fullyCharged
        case yesNo, passcode, trusted, activation, unixDate, diagnostic, diskCalculation
    }
    private struct Definition {
        let key: String
        let title: String
        let detail: String
        let kind: Kind
    }
    private static let definitions: [Definition] = [
        .init(key: "TotalDiskCapacity", title: "Total Storage Capacity", detail: "The device’s reported physical storage capacity.", kind: .bytes),
        .init(key: "AmountDataAvailable", title: "Currently Available Space", detail: "Space currently reported as available for writing; used by the status bar.", kind: .bytes),
        .init(key: "AmountDataReserved", title: "Reserved Data Space", detail: "Space reserved by the device for data operations.", kind: .bytes),
        .init(key: "AmountRestoreAvailable", title: "Space Available for Restore", detail: "Space the device reports as available for restore operations.", kind: .bytes),
        .init(key: "TotalDataCapacity", title: "Data Partition Capacity", detail: "Capacity of the partition used for apps and personal data.", kind: .bytes),
        .init(key: "TotalDataAvailable", title: "Data Partition Available Space", detail: "A separate system capacity statistic; its accounting differs from currently available space.", kind: .bytes),
        .init(key: "TotalSystemCapacity", title: "System Partition Capacity", detail: "Capacity of the partition used by the operating system.", kind: .bytes),
        .init(key: "TotalSystemAvailable", title: "System Partition Available Space", detail: "Available space in the system partition; zero does not mean personal storage is full.", kind: .bytes),
        .init(key: "CalculateDiskUsage", title: "Storage Statistics", detail: "Whether the device returned storage usage statistics.", kind: .diskCalculation),
        .init(key: "NANDInfo", title: "Storage Chip Diagnostics", detail: "Internal chip diagnostics, not a storage capacity or health score.", kind: .diagnostic),
        .init(key: "BatteryCurrentCapacity", title: "Battery Level", detail: "The device’s current battery percentage.", kind: .percent),
        .init(key: "BatteryIsCharging", title: "Charging Status", detail: "Whether the battery is charging now.", kind: .charging),
        .init(key: "ExternalConnected", title: "External Power", detail: "Whether the device is connected to an external power source.", kind: .externalPower),
        .init(key: "ExternalChargeCapable", title: "External Charging Support", detail: "Whether the connected power source can charge the device.", kind: .supported),
        .init(key: "FullyCharged", title: "Fully Charged", detail: "Whether the device reports that charging is complete.", kind: .fullyCharged),
        .init(key: "HasBattery", title: "Battery Present", detail: "Whether this device reports a built-in battery.", kind: .yesNo),
        .init(key: "GasGaugeCapability", title: "Battery Measurement Support", detail: "Whether the device reports support for battery measurement.", kind: .supported),
        .init(key: "DeviceName", title: "Device Name", detail: "The name assigned to this device.", kind: .text),
        .init(key: "DeviceClass", title: "Device Type", detail: "The device family, such as iPhone or iPad.", kind: .text),
        .init(key: "ProductType", title: "Hardware Model Identifier", detail: "Apple’s internal hardware model identifier.", kind: .text),
        .init(key: "HardwareModel", title: "Hardware Board Model", detail: "The device’s internal board model.", kind: .text),
        .init(key: "ProductVersion", title: "System Version", detail: "The operating system version installed on the device.", kind: .text),
        .init(key: "BuildVersion", title: "System Build", detail: "The build identifier of the installed operating system.", kind: .text),
        .init(key: "SerialNumber", title: "Serial Number", detail: "The device’s serial number.", kind: .text),
        .init(key: "ModelNumber", title: "Model Number", detail: "The product’s model or part number.", kind: .text),
        .init(key: "RegionInfo", title: "Sales Region Code", detail: "The product’s sales region code.", kind: .text),
        .init(key: "ActivationState", title: "Activation Status", detail: "Whether the device has completed activation.", kind: .activation),
        .init(key: "PasswordProtected", title: "Screen Lock Passcode", detail: "Whether a device passcode is configured; the password itself is not read.", kind: .passcode),
        .init(key: "TrustedHostAttached", title: "Computer Trust", detail: "Whether the device reports that this computer is trusted.", kind: .trusted),
        .init(key: "CPUArchitecture", title: "Processor Architecture", detail: "The instruction-set architecture used by the processor.", kind: .text),
        .init(key: "WiFiAddress", title: "Wi-Fi Hardware Address", detail: "The hardware address of the Wi-Fi interface.", kind: .text),
        .init(key: "BluetoothAddress", title: "Bluetooth Hardware Address", detail: "The hardware address of the Bluetooth interface.", kind: .text),
        .init(key: "EthernetAddress", title: "Ethernet Hardware Address", detail: "The hardware address of the Ethernet interface.", kind: .text),
        .init(key: "UniqueDeviceID", title: "Device Identifier", detail: "The identifier used to associate a device with its backups.", kind: .text),
        .init(key: "TimeZone", title: "Time Zone", detail: "The time zone configured on the device.", kind: .text),
        .init(key: "TimeIntervalSince1970", title: "Device Date and Time", detail: "The device’s reported clock time.", kind: .unixDate),
        .init(key: "TelephonyCapability", title: "Cellular Support", detail: "Whether the device supports cellular telephony.", kind: .supported),
        .init(key: "BasebandVersion", title: "Modem Firmware", detail: "The firmware version of the cellular modem.", kind: .text),
        .init(key: "IMEI", title: "IMEI", detail: "The mobile network equipment identifier.", kind: .text),
        .init(key: "InternationalMobileEquipmentIdentity", title: "IMEI", detail: "The mobile network equipment identifier.", kind: .text),
        .init(key: "InternationalMobileEquipmentIdentity2", title: "Secondary IMEI", detail: "The secondary mobile network equipment identifier.", kind: .text)
    ]

    static func rows(values: [String: String]) -> [Row] {
        definitions.compactMap { definition in
            guard let raw = values[definition.key], !raw.isEmpty else { return nil }
            return Row(id: definition.key, title: localize(definition.title),
                       value: format(raw, kind: definition.kind), detail: localize(definition.detail))
        }
    }

    private static func localize(_ text: String) -> String {
        String(localized: String.LocalizationValue(text))
    }

    private static func format(_ raw: String, kind: Kind) -> String {
        switch kind {
        case .text: return raw
        case .bytes:
            guard let bytes = Int64(raw), bytes >= 0 else { return localize("Unknown") }
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        case .percent:
            guard let number = Int(raw), (0...100).contains(number) else { return localize("Unknown") }
            return "\(number)%"
        case .unixDate:
            guard let seconds = Double(raw), seconds.isFinite, seconds >= 0 else { return localize("Unknown") }
            return Date(timeIntervalSince1970: seconds).formatted(date: .abbreviated, time: .standard)
        case .diagnostic: return localize("Internal Diagnostics Received")
        case .diskCalculation:
            return localize(raw == "OkilyDokily" ? "Storage Statistics Complete" : "Storage Statistics Unavailable")
        case .activation:
            switch raw {
            case "Activated": return localize("Activated")
            case "Unactivated": return localize("Not Activated")
            default: return localize("Activation Required")
            }
        default:
            let flag: Bool
            switch raw.lowercased() {
            case "true", "yes", "1": flag = true
            case "false", "no", "0": flag = false
            default: return localize("Unknown")
            }
            let pair: (String, String)
            switch kind {
            case .charging: pair = ("Charging", "Not Charging")
            case .externalPower: pair = ("Connected", "Not Connected")
            case .supported: pair = ("Supported", "Not Supported")
            case .fullyCharged: pair = ("Charge Complete", "Not Fully Charged")
            case .passcode: pair = ("Passcode Set", "No Passcode Set")
            case .trusted: pair = ("Computer Trusted", "Computer Not Trusted")
            default: pair = ("Yes", "No")
            }
            return localize(flag ? pair.0 : pair.1)
        }
    }

    #if DEBUG
    static func verify() -> Bool {
        let sample = rows(values: [
            "AmountDataAvailable": "6029484032", "AmountDataReserved": "209715200",
            "TotalDiskCapacity": "256000000000", "BatteryCurrentCapacity": "81",
            "BatteryIsCharging": "true", "CalculateDiskUsage": "OkilyDokily",
            "NANDInfo": "01000000DEADBEEF", "PrivateUnknownField": "private payload",
        ])
        let byID = Dictionary(uniqueKeysWithValues: sample.map { ($0.id, $0) })
        return sample.count == 7
            && byID["AmountDataAvailable"]?.value.contains("GB") == true
            && byID["AmountDataReserved"]?.value.contains("MB") == true
            && byID["TotalDiskCapacity"]?.value.contains("256") == true
            && byID["BatteryCurrentCapacity"]?.value == "81%"
            && byID["BatteryIsCharging"]?.value == localize("Charging")
            && byID["CalculateDiskUsage"]?.value == localize("Storage Statistics Complete")
            && byID["NANDInfo"]?.value.contains("DEADBEEF") == false
            && rows(values: ["BatteryCurrentCapacity": "101", "AmountDataAvailable": "-1"])
                .allSatisfy { $0.value == localize("Unknown") }
    }
    #endif
}
