//
//  Device.swift
//  BBackupp
//
//  Created by 秋星桥 on 2024/1/4.
//

import Combine
import Foundation

struct Device: Codable, Identifiable, Hashable, Equatable, CopyableCodable {
    typealias ID = String

    var id: String {
        udid
    }

    var udid: String
    var deviceRecord: AppleMobileDeviceManager.DeviceRecord {
        didSet { deviceRecordLastUpdate = Date() }
    }

    var deviceRecordLastUpdate: Date?
    var pairRecord: PairRecord

    enum ExtraKey: String, Codable {
        case preferredIcon
    }

    var extra: [ExtraKey: String] = .init()

    var possibleNetworkAddress: [String] = []

    var deviceName: String {
        deviceRecord.deviceName ?? "Unknown"
    }

    var deviceSystemIcon: String {
        if let icon = extra[.preferredIcon], !icon.isEmpty {
            return icon
        }
        if let icon = deviceRecord.deviceClass?.lowercased() {
            return icon
        }
        return "questionmark.circle"
    }

    init(
        udid: String = "",
        deviceRecord: AppleMobileDeviceManager.DeviceRecord = .init(),
        pairRecord: PairRecord = .init(),
        extra: [ExtraKey: String] = .init(),
        possibleNetworkAddress: [String] = []
    ) {
        self.udid = udid.uppercased()
        self.deviceRecord = deviceRecord
        self.pairRecord = pairRecord
        self.extra = extra
        self.possibleNetworkAddress = possibleNetworkAddress
    }
}
