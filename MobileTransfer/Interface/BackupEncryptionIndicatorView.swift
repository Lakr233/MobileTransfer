//
//  BackupEncryptionIndicatorView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import SwiftUI

struct BackupEncryptionIndicatorView: View {
    @Environment(ViewModel.self) var vm

    enum BackupEncryptionStatus {
        case finding
        case unknown
        case yes
        case no
    }

    @State var status: BackupEncryptionStatus = .finding

    @State var helpURL: String?

    let timer = Timer
        .publish(every: 5, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        CardContentView {
            CardContentHeader(icon: "lock", title: "Backup Encryption") {
                switch status {
                case .finding: Image(systemName: "hourglass")
                case .unknown: Image(systemName: "questionmark.circle.fill")
                case .yes: Image(systemName: "lock.fill")
                case .no: Image(systemName: "lock.open.fill")
                }
            }
            switch status {
            case .finding:
                Text("Checking backup encryption...")
            case .unknown:
                Text("Could not check the backup encryption status of this device, please proceed with caution.")
                    .foregroundStyle(.red)
                    .underline()
            case .yes:
                Text("This device has a backup password set, you will need the password to use this backup.")
                Divider()
                CheckLabel(check: true, text: "Encrypted Backup")
                CheckLabel(check: true, text: "System Data (photos, contacts, messages, emails...)")
                CheckLabel(check: true, text: "App Data (data from apps installed from the App Store)")
                CheckLabel(check: true, text: "Encrypted Data (keychain, etc.)")
                CheckLabel(check: false, text: "Data Excluded By App (some game resources, etc.)")
                Divider()
                Button {
                    helpURL = "https://support.apple.com/108313"
                } label: {
                    Text("Forgot password?")
                        .underline()
                        .foregroundStyle(.accent)
                }
                .buttonStyle(.plain)
            case .no:
                Text("This device does not have a backup password set.")
                Text("If you continue without encryption, the backup will not include sensitive data. Restoring a device from the backup will result in loss of stored passwords, Health and HomeKit data.")
                    .foregroundStyle(.red)
                    .underline()
                Divider()
                CheckLabel(check: false, text: "Encrypted Backup")
                CheckLabel(check: true, text: "System Data (photos, contacts, messages, emails...)")
                CheckLabel(check: true, text: "App Data (data from apps installed from the App Store)")
                CheckLabel(check: false, text: "Encrypted Data (keychain, etc.)")
                CheckLabel(check: false, text: "Data Excluded By App (some game resources, etc.)")
                Divider()
                Button {
                    helpURL = "https://support.apple.com/108353"
                } label: {
                    Text("Learn More (Enable Encrypted Backup)")
                        .underline()
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.spring, value: status)
        .onAppear { updateDeviceStatus() }
        .onReceive(timer) { _ in updateDeviceStatus() }
        .sheet(item: $helpURL) {
            WebSheetView(url: URL(string: $0))
        }
    }

    struct CheckLabel: View {
        let check: Bool
        let text: LocalizedStringKey

        var body: some View {
            HStack(spacing: 8) {
                Image(
                    systemName: check
                        ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .foregroundStyle(check ? .green : .red)
                Text(text)
            }
        }
    }

    func updateDeviceStatus() {
        guard let udid = vm.deviceIdentifier else { return }
        if status == .unknown { status = .finding }
        DispatchQueue.global().async {
            var enabled: Bool? = nil
            if let read = AppleMobileDeviceManager.shared.readFromLockdown(
                udid: udid,
                domain: "com.apple.mobile.backup",
                key: nil,
                connection: .usb
            ), let dic = read.value as? [String: Any],
            let value = dic["WillEncrypt"] as? Bool
            { enabled = value }

            DispatchQueue.main.async {
                withAnimation(.spring) {
                    if let enabled {
                        status = enabled ? .yes : .no
                    } else {
                        status = .unknown
                    }
                    vm.backupEncrypted = enabled ?? false
                }
            }
        }
    }
}
