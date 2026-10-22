//
//  FindDeviceView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import AppleMobileDeviceLibrary
import SwiftUI

struct ConnectedDevice: Codable, Identifiable, Hashable, Equatable {
    var id: String {
        udid
    }

    var udid: String
    var deviceRecord: AppleMobileDeviceManager.DeviceRecord? {
        didSet { assert(deviceRecord?.uniqueDeviceID == udid) }
    }

    var trusted: Bool {
        deviceRecord?.valueFor("TrustedHostAttached") ?? false
    }

    var deviceName: String? {
        guard let name = deviceRecord?.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else { return nil }
        return name
    }

    var modelName: String? {
        if let productType = deviceRecord?.productType,
           let modelName = Self.modelNames[productType]
        {
            return modelName
        }
        return deviceRecord?.deviceClass
    }

    static let modelNames: [String: String] = [
        "iPhone12,1": "iPhone 11",
        "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2nd generation)",
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,6": "iPhone SE (3rd generation)",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,5": "iPhone 16e",
        "iPhone18,1": "iPhone 17 Pro",
        "iPhone18,2": "iPhone 17 Pro Max",
        "iPhone18,3": "iPhone 17",
        "iPhone18,4": "iPhone Air",
        "iPhone18,5": "iPhone 17e",
    ]

    var deviceSystemIcon: String {
        deviceRecord?.deviceClass?.lowercased() ?? "questionmark.circle"
    }
}

struct FindDeviceView: View {
    @Environment(ViewModel.self) var vm

    let timer = Timer
        .publish(every: 5, on: .main, in: .common)
        .autoconnect()

    @State private var isScanning = false
    @State private var scanID: UUID?
    @State private var deviceList: [ConnectedDevice] = []
    @State private var openTrustPage: Bool = false

    var title: LocalizedStringKey {
        if !deviceList.isEmpty {
            "Devices found"
        } else if isScanning {
            "Scanning for devices..."
        } else {
            "Please connect your device to this computer via a cable"
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button {
                    vm.navigationArray = [.welcome]
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
            if !deviceList.isEmpty {
                Text(title)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
                    .multilineTextAlignment(.center)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    ForEach(deviceList) { device in
                        UnregisteredDeviceView(device: device) {
                            if !device.trusted {
                                openTrustPage = true
                                DispatchQueue.global(qos: .userInitiated).async {
                                    AppleMobileDeviceManager.shared.sendPairRequest(
                                        udid: device.id,
                                        connection: .usb
                                    )
                                }
                            } else {
                                selectDevice(device)
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                    Spacer().frame(height: 128)
                }
                .frame(maxWidth: .infinity)
                .padding(32)
            }
            .overlay {
                if deviceList.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "laptopcomputer.and.iphone")
                            .font(.system(size: 96, weight: .ultraLight))
                            .foregroundStyle(.primary.opacity(0.7))
                            .frame(width: 128, height: 80)
                        Text(title)
                            .contentTransition(.numericText())
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .padding(-32)
            .frame(maxWidth: 400)
        }
        .sheet(isPresented: $openTrustPage) {
            DeviceTrustView().onDisappear {
                scan()
            }
        }
        .animation(.spring, value: isScanning)
        .animation(.spring, value: deviceList)
        .onAppear { scan() }
        .onAppear { vm.deviceIdentifier = nil }
        .onReceive(timer) { _ in scan() }
        .onDisappear {
            scanID = nil
            isScanning = false
        }
    }

    func scan() {
        guard scanID == nil else { return }
        let id = UUID()
        scanID = id
        isScanning = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            guard vm.page == .findDevice, scanID == id else { return }
            isScanning = false
        }
        DispatchQueue.global().async {
            autoreleasepool {
                let scan = AppleMobileDeviceManager.shared
                    .listDeviceIdentifiers()
                    .compactMap { AppleMobileDeviceManager.shared.obtainDeviceInfo(udid: $0, connection: .usb) }
                    .compactMap { input -> ConnectedDevice? in
                        guard let udid = input.uniqueDeviceID else { return nil }
                        return ConnectedDevice(udid: udid, deviceRecord: input)
                    }
                    .sorted { $0.udid < $1.udid }
                DispatchQueue.main.async {
                    guard vm.page == .findDevice, scanID == id else { return }
                    scanID = nil
                    isScanning = false
                    deviceList = scan
                }
            }
        }
    }

    private func selectDevice(_ device: ConnectedDevice) {
        vm.deviceIdentifier = device.udid
        vm.selectedDeviceName = device.deviceName
        vm.selectedDeviceModel = device.modelName
        vm.selectedDeviceVersion = device.deviceRecord?.productVersion
        vm.selectedDeviceIcon = device.deviceSystemIcon
        vm.selectedDeviceRecord = device.deviceRecord

        var backupName: String = device.deviceRecord?.deviceName ?? ""
        if backupName.isEmpty { backupName = device.udid }

        switch vm.mode {
        case .unspecified:
            assertionFailure()
            vm.page = .welcome
        case .backup:
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyyMMdd-HHmm"
            fmt.locale = .init(identifier: "en_US_POSIX")
            let date = fmt.string(from: Date())
            vm.backupLocation = ViewModel.defaultBackupLocation
                .appendingPathComponent("\(backupName)-\(date).mobiletransfer")
                .path
            vm.page = .prepareBackup
        case .restore:
            vm.page = .prepareRestore
        }
    }
}

private struct UnregisteredDeviceView: View {
    let device: ConnectedDevice
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: device.deviceSystemIcon)
                    .font(.title2)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    if let name = device.deviceName {
                        Text(name)
                            .font(.system(.headline, design: .rounded))
                            .lineLimit(1)
                    } else {
                        Text("Unnamed Device")
                            .font(.system(.headline, design: .rounded))
                    }
                    if let modelName = device.modelName {
                        Text(modelName)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Unknown Model")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(.headline, design: .rounded))
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .itmGlassSurface(cornerRadius: 18, interactive: true)
        }
        .buttonStyle(.plain)
    }
}

struct DeviceTrustView: View {
    var body: some View {
        MessageBoxView {
            HStack {
                Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                    .foregroundColor(.red)
                Text("Device Locked").bold()
            }
            Text("Please trust this computer on your device.")
            Text("If you don't see the confirmation prompt, disconnect the device from your computer and try again.")
        }
    }
}
