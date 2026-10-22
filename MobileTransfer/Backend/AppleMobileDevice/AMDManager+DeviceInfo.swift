//
//  AMDManager+DeviceInfo.swift
//
//
//  Created by QAQ on 2023/8/11.
//

import AppleMobileDeviceLibrary
import Foundation

public extension AppleMobileDeviceManager {
    func listDeviceIdentifiers() -> [String] {
        var deviceIdentifier = Set<String>()
        var dev_list: UnsafeMutablePointer<idevice_info_t?>?
        var count: Int32 = 0
        idevice_get_device_list_extended(&dev_list, &count)
        if let dev_list {
            for idx in 0 ..< Int(count) {
                if let udidCString = dev_list[idx]?.pointee.udid {
                    if let udid = String(cString: udidCString, encoding: .utf8) {
                        deviceIdentifier.insert(udid)
                    }
                }
            }
            idevice_device_list_extended_free(dev_list)
        }
        return Array(deviceIdentifier)
    }

    func remoteDeviceHandlerIdentifier(
        udid: String,
        connection: ConnectionMethod = configuration.connectionMethod
    ) -> UInt32? {
        var handle: UInt32 = 0
        var handleHasValue = false
        requireDevice(udid: udid, connection: connection) { device in
            guard let device else { return }
            handleHasValue = idevice_get_handle(device, &handle) == IDEVICE_E_SUCCESS
        }
        return handleHasValue ? handle : nil
    }

    class DeviceRecord: CodableRecord {
        public var activationState: String? {
            valueFor("ActivationState")
        }

        public var activationStateAcknowledged: Bool? {
            valueFor("ActivationStateAcknowledged")
        }

        public var basebandActivationTicketVersion: String? {
            valueFor("BasebandActivationTicketVersion")
        }

        public var basebandCertId: Int? {
            valueFor("BasebandCertId")
        }

        public var basebandChipID: Int? {
            valueFor("BasebandChipID")
        }

        public var basebandMasterKeyHash: String? {
            valueFor("BasebandMasterKeyHash")
        }

        public var basebandRegionSKU: Data? {
            valueFor("BasebandRegionSKU")
        }

        public var basebandSerialNumber: Data? {
            valueFor("BasebandSerialNumber")
        }

        public var basebandStatus: String? {
            valueFor("BasebandStatus")
        }

        public var basebandVersion: String? {
            valueFor("BasebandVersion")
        }

        public var bluetoothAddress: String? {
            valueFor("BluetoothAddress")
        }

        public var boardId: Int? {
            valueFor("BoardId")
        }

        public var bootSessionID: String? {
            valueFor("BootSessionID")
        }

        public var brickState: Bool? {
            valueFor("BrickState")
        }

        public var buildVersion: String? {
            valueFor("BuildVersion")
        }

        public var cpuArchitecture: String? {
            valueFor("CPUArchitecture")
        }

        public var certID: Int? {
            valueFor("CertID")
        }

        public var chipID: Int? {
            valueFor("ChipID")
        }

        public var chipSerialNo: Data? {
            valueFor("ChipSerialNo")
        }

        public var deviceClass: String? {
            valueFor("DeviceClass")
        }

        public var deviceColor: String? {
            valueFor("DeviceColor")
        }

        public var deviceName: String? {
            valueFor("DeviceName")
        }

        public var dieID: Int? {
            valueFor("DieID")
        }

        public var ethernetAddress: String? {
            valueFor("EthernetAddress")
        }

        public var firmwareVersion: String? {
            valueFor("FirmwareVersion")
        }

        public var fusingStatus: Int? {
            valueFor("FusingStatus")
        }

        public var gid1: String? {
            valueFor("GID1")
        }

        public var gid2: String? {
            valueFor("GID2")
        }

        public var hardwareModel: String? {
            valueFor("HardwareModel")
        }

        public var hardwarePlatform: String? {
            valueFor("HardwarePlatform")
        }

        public var hasSiDP: Bool? {
            valueFor("HasSiDP")
        }

        public var humanReadableProductVersionString: String? {
            valueFor("HumanReadableProductVersionString")
        }

        public var iTunesHasConnected: Bool? {
            valueFor("iTunesHasConnected")
        }

        public var integratedCircuitCardIdentity2: String? {
            valueFor("IntegratedCircuitCardIdentity2")
        }

        public var integratedCircuitCardIdentity: String? {
            valueFor("IntegratedCircuitCardIdentity")
        }

        public var internationalMobileEquipmentIdentity2: String? {
            valueFor("InternationalMobileEquipmentIdentity2")
        }

        public var internationalMobileEquipmentIdentity: String? {
            valueFor("InternationalMobileEquipmentIdentity")
        }

        public var internationalMobileSubscriberIdentity2: String? {
            valueFor("InternationalMobileSubscriberIdentity2")
        }

        public var internationalMobileSubscriberIdentity: String? {
            valueFor("InternationalMobileSubscriberIdentity")
        }

        public var internationalMobileSubscriberIdentityOverride: Bool? {
            valueFor("InternationalMobileSubscriberIdentityOverride")
        }

        public var kCTPostponementInfoPRIVersion: String? {
            valueFor("kCTPostponementInfoPRIVersion")
        }

        public var kCTPostponementInfoPRLName: Int? {
            valueFor("kCTPostponementInfoPRLName")
        }

        public var kCTPostponementInfoServiceProvisioningState: Bool? {
            valueFor("kCTPostponementInfoServiceProvisioningState")
        }

        public var kCTPostponementStatus: String? {
            valueFor("kCTPostponementStatus")
        }

        public var mlbSerialNumber: String? {
            valueFor("MLBSerialNumber")
        }

        public var mobileSubscriberCountryCode: String? {
            valueFor("MobileSubscriberCountryCode")
        }

        public var mobileSubscriberNetworkCode: String? {
            valueFor("MobileSubscriberNetworkCode")
        }

        public var modelNumber: String? {
            valueFor("ModelNumber")
        }

        public var priVersion_Major: Int? {
            valueFor("PRIVersion_Major")
        }

        public var priVersion_Minor: Int? {
            valueFor("PRIVersion_Minor")
        }

        public var priVersion_ReleaseNo: Int? {
            valueFor("PRIVersion_ReleaseNo")
        }

        public var pairRecordProtectionClass: Int? {
            valueFor("PairRecordProtectionClass")
        }

        public var partitionType: String? {
            valueFor("PartitionType")
        }

        public var passwordProtected: Bool? {
            valueFor("PasswordProtected")
        }

        public var phoneNumber: String? {
            valueFor("PhoneNumber")
        }

        public var pkHash: Data? {
            valueFor("PkHash")
        }

        public var productName: String? {
            valueFor("ProductName")
        }

        public var productType: String? {
            valueFor("ProductType")
        }

        public var productVersion: String? {
            valueFor("ProductVersion")
        }

        public var productionSOC: Bool? {
            valueFor("ProductionSOC")
        }

        public var protocolVersion: String? {
            valueFor("ProtocolVersion")
        }

        public var proximitySensorCalibration: Data? {
            valueFor("ProximitySensorCalibration")
        }

        public var regionInfo: String? {
            valueFor("RegionInfo")
        }

        public var sim1IsEmbedded: Bool? {
            valueFor("SIM1IsEmbedded")
        }

        public var sim2GID1: Data? {
            valueFor("SIM2GID1")
        }

        public var sim2GID2: Data? {
            valueFor("SIM2GID2")
        }

        public var sim2IsEmbedded: Bool? {
            valueFor("SIM2IsEmbedded")
        }

        public var simGID1: Data? {
            valueFor("SIMGID1")
        }

        public var simGID2: Data? {
            valueFor("SIMGID2")
        }

        public var simStatus: String? {
            valueFor("SIMStatus")
        }

        public var simTrayStatus: String? {
            valueFor("SIMTrayStatus")
        }

        public var serialNumber: String? {
            valueFor("SerialNumber")
        }

        public var softwareBehavior: Data? {
            valueFor("SoftwareBehavior")
        }

        public var softwareBundleVersion: String? {
            valueFor("SoftwareBundleVersion")
        }

        public var telephonyCapability: Bool? {
            valueFor("TelephonyCapability")
        }

        public var timeIntervalSince1970: Double? {
            valueFor("TimeIntervalSince1970")
        }

        public var timeZone: String? {
            valueFor("TimeZone")
        }

        public var timeZoneOffsetFromUTC: Int? {
            valueFor("TimeZoneOffsetFromUTC")
        }

        public var uniqueChipID: Int? {
            valueFor("UniqueChipID")
        }

        public var uniqueDeviceID: String? {
            valueFor("UniqueDeviceID")
        }

        public var useRaptorCerts: Bool? {
            valueFor("UseRaptorCerts")
        }

        public var uses24HourClock: Bool? {
            valueFor("Uses24HourClock")
        }

        public var wifiAddress: String? {
            valueFor("WiFiAddress")
        }
    }

    class BatteryRecord: CodableRecord {
        public var batteryCurrentCapacity: Int? {
            valueFor("BatteryCurrentCapacity")
        }

        public var batteryIsCharging: Bool? {
            valueFor("BatteryIsCharging")
        }

        public var externalChargeCapable: Bool? {
            valueFor("ExternalChargeCapable")
        }

        public var externalConnected: Bool? {
            valueFor("ExternalConnected")
        }

        public var fullyCharged: Bool? {
            valueFor("FullyCharged")
        }

        public var gasGaugeCapability: Bool? {
            valueFor("GasGaugeCapability")
        }

        public var hasBattery: Bool? {
            valueFor("HasBattery")
        }
    }

    internal func lockdownGetValue<T: Codable>(
        client: lockdownd_client_t?,
        domain: String? = nil,
        key: String? = nil
    ) -> T? {
        guard let client else { return nil }
        var plist: plist_t?
        defer { if let plist { plist_free(plist) } }
        lockdownd_get_value(client, domain, key, &plist)
        guard let data = AMDUtils.read_plist_to_binary_data(plist: plist),
              let ret = try? PropertyListDecoder().decode(T.self, from: data)
        else { return nil }
        return ret
    }

    /// Read the native Boolean directly, including false on devices without encryption.
    func readBackupEncryptionStatus(udid: String) -> Bool? {
        var result: Bool?
        requireDevice(udid: udid, connection: .usb) { device in
            guard let device else { return }
            requireLockdownClient(device: device, handshake: true) { client in
                guard let client else { return }
                var node: plist_t?
                defer { if let node { plist_free(node) } }
                let error = lockdownd_get_value(client, "com.apple.mobile.backup", "WillEncrypt", &node)
                // New devices can omit WillEncrypt until encryption has been configured.
                // Match idevicebackup2, but first verify the backup domain is readable.
                if error == LOCKDOWN_E_MISSING_VALUE {
                    let values: AnyCodable? = lockdownGetValue(client: client, domain: "com.apple.mobile.backup")
                    if let domain = values?.value as? [String: Any], domain["Version"] != nil {
                        result = false
                    }
                    return
                }
                guard error == LOCKDOWN_E_SUCCESS, let node,
                      plist_get_node_type(node) == PLIST_BOOLEAN else { return }
                var value: UInt8 = 0
                plist_get_bool_val(node, &value)
                result = value != 0
            }
        }
        return result
    }

    /// Changes only the explicitly selected USB device and verifies the saved value.
    func renameDevice(udid: String, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "iTM.DeviceName", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "设备名称不能为空。"])
        }
        var failure: Error? = NSError(domain: "iTM.DeviceName", code: 2,
                                     userInfo: [NSLocalizedDescriptionKey: "无法连接设备，请解锁 iPhone 并确认信任此 Mac 后重试。"])
        requireDevice(udid: udid, connection: .usb) { device in
            guard let device else { return }
            requireLockdownClient(device: device, handshake: true) { client in
                guard let client else { return }
                // lockdownd_set_value takes ownership and frees the value with its request.
                let node = plist_new_string(trimmed)
                let status = lockdownd_set_value(client, nil, "DeviceName", node)
                guard status == LOCKDOWN_E_SUCCESS else {
                    failure = NSError(domain: "iTM.DeviceName", code: Int(status.rawValue),
                                      userInfo: [NSLocalizedDescriptionKey: "修改名称失败，请解锁 iPhone 后重试。（错误 \(status.rawValue)）"])
                    return
                }
                var savedNode: plist_t?
                defer { if let savedNode { plist_free(savedNode) } }
                let readStatus = lockdownd_get_value(client, nil, "DeviceName", &savedNode)
                var savedName: String?
                if readStatus == LOCKDOWN_E_SUCCESS, let savedNode,
                   plist_get_node_type(savedNode) == PLIST_STRING {
                    var length: UInt64 = 0
                    if let pointer = plist_get_string_ptr(savedNode, &length) {
                        savedName = String(cString: pointer)
                    }
                }
                guard savedName == trimmed else {
                    failure = NSError(domain: "iTM.DeviceName", code: 3,
                                      userInfo: [NSLocalizedDescriptionKey: "未能确认新名称已保存，请重新读取设备信息后再试。"])
                    return
                }
                failure = nil
            }
        }
        if let failure { throw failure }
    }

    func readFromLockdown(
        udid: String,
        domain: String? = nil,
        key: String? = nil,
        connection: ConnectionMethod = configuration.connectionMethod
    ) -> AnyCodable? {
        var result: AnyCodable?
        requireDevice(udid: udid, connection: connection) { device in
            guard let device else { return }
            requireLockdownClient(device: device, handshake: true) { client in
                guard let client else { return }
                result = lockdownGetValue(client: client, domain: domain, key: key)
            }
            if result != nil { return }
            requireLockdownClient(device: device, handshake: false) { client in
                guard let client else { return }
                result = lockdownGetValue(client: client, domain: domain, key: key)
            }
        }
        return result
    }

    /// Reads related domains within one scoped USB connection and Lockdown session.
    /// Missing domains retain the existing non-handshake fallback. Clients never escape
    /// their owning closure and are not shared across background reads.
    func readLockdownValues(
        udid: String,
        domains: [String],
        connection: ConnectionMethod = configuration.connectionMethod
    ) -> [String: AnyCodable] {
        var result: [String: AnyCodable] = [:]
        requireDevice(udid: udid, connection: connection) { device in
            guard let device else { return }
            requireLockdownClient(device: device, handshake: true) { client in
                guard let client else { return }
                for domain in domains {
                    result[domain] = lockdownGetValue(client: client, domain: domain)
                }
            }
            let missing = domains.filter { result[$0] == nil }
            guard !missing.isEmpty else { return }
            requireLockdownClient(device: device, handshake: false) { client in
                guard let client else { return }
                for domain in missing {
                    result[domain] = lockdownGetValue(client: client, domain: domain)
                }
            }
        }
        return result
    }

    func obtainDeviceInfo(
        udid: String,
        domain: String? = nil,
        key: String? = nil,
        connection: ConnectionMethod = configuration.connectionMethod
    ) -> DeviceRecord? {
        guard let dic = readFromLockdown(udid: udid, domain: domain, key: key, connection: connection) else {
            return nil
        }
        return .init(store: dic)
    }

    func obtainDeviceBatteryInfo(
        udid: String,
        connection: ConnectionMethod = configuration.connectionMethod
    ) -> BatteryRecord? {
        guard let dic = readFromLockdown(udid: udid, domain: "com.apple.mobile.battery", key: nil, connection: connection) else {
            return nil
        }
        return .init(store: dic)
    }
}
