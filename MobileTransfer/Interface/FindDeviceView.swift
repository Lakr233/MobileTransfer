//
//  FindDeviceView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import AppleMobileDeviceLibrary
import SwiftUI

private struct UnregisteredDevice: Codable, Identifiable, Hashable, Equatable {
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

    var deviceName: String {
        deviceRecord?.deviceName ?? "Unknown"
    }

    var productType: String {
        deviceRecord?.productType ?? "Unknown"
    }

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
    @State private var deviceList: [UnregisteredDevice] = []
    @State private var openTrustPage: Bool = false

    var title: LocalizedStringKey {
        if isScanning {
            "Scanning for devices..."
        } else {
            "Please connect your device to this computer via a cable"
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())
                .multilineTextAlignment(.center)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    ForEach(deviceList) { device in
                        UnregisteredDeviceView(device: device) {
                            if !device.trusted {
                                AppleMobileDeviceManager.shared.sendPairRequest(
                                    udid: device.id,
                                    connection: .usb
                                )
                            }
                            selectDevice(device.id)
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
                    Image(.computerSmartphoneConnect)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 128, height: 128)
                        .frame(maxHeight: .infinity, alignment: .center)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .padding(-32)
            .frame(maxWidth: 400)
        }
        .sheet(isPresented: $openTrustPage) {
            TrustPageView().onDisappear {
                scan()
            }
        }
        .animation(.spring, value: isScanning)
        .animation(.spring, value: deviceList)
        .onAppear { scan() }
        .onAppear { vm.deviceIdentifier = nil }
        .onReceive(timer) { _ in scan() }
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        DispatchQueue.global().async {
            autoreleasepool {
                let scan = AppleMobileDeviceManager.shared
                    .listDeviceIdentifiers()
                    .compactMap { AppleMobileDeviceManager.shared.obtainDeviceInfo(udid: $0, connection: .usb) }
                    .compactMap { input -> UnregisteredDevice? in
                        guard let udid = input.uniqueDeviceID else { return nil }
                        return UnregisteredDevice(udid: udid, deviceRecord: input)
                    }
                    .sorted { $0.udid < $1.udid }
                sleep(1)
                DispatchQueue.main.async {
                    isScanning = false
                    deviceList = scan
                }
            }
        }
    }

    private func selectDevice(_ did: String) {
        guard let rawDevice = AppleMobileDeviceManager.shared.obtainDeviceInfo(udid: did, connection: .usb),
              let udid = rawDevice.uniqueDeviceID
        else {
            assertionFailure()
            return
        }
        assert(udid == did)
        let device = UnregisteredDevice(udid: udid, deviceRecord: rawDevice)
        guard device.trusted else {
            openTrustPage = true
            return
        }
        vm.deviceIdentifier = device.udid

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
            vm.pickSaveLocation()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                vm.page = .prepareBackup
            }
        case .restore:
            if vm.restoreLocation == nil {
                vm.pickRestoreArchive()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                vm.page = .prepareRestore
            }
        }
    }
}

private struct UnregisteredDeviceView: View {
    let device: UnregisteredDevice
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: device.deviceSystemIcon)
                        Text(device.productType)
                            .lineLimit(1)
                    }
                    .font(.system(.headline, design: .rounded))
                    Text(device.trusted ? device.deviceName : device.udid)
                        .font(.footnote)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(.headline, design: .rounded))
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.background.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct TrustPageView: View {
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
