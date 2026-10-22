//
//  BackupEncryptionIndicatorView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import AuxiliaryExecute
import Combine
import SwiftUI

struct BackupEncryptionIndicatorView: View {
    @Environment(ViewModel.self) private var vm
    @Binding var isEnabling: Bool

    // The parent owns the initial batched read and retains status across tab changes.
    @Binding var status: Status

    enum Status: Equatable {
        case finding
        case unknown
        case enabled
        case disabled
    }

    @State private var isReadingStatus = false
    @State private var showPasswordSheet = false
    @State private var showEnableError = false
    @State private var password = ""
    @State private var confirmation = ""

    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if status == .enabled {
                    Label("Encrypted Backup", systemImage: "lock.shield.fill")
                    Label("Enabled", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                } else {
                    Toggle("Encrypted Backup", isOn: Binding(
                        get: { false },
                        set: { if $0 { showPasswordSheet = true } }
                    ))
                    .toggleStyle(.checkbox)
                    .disabled(isEnabling || status != .disabled)
                }

                Spacer()

                if isEnabling || status == .finding {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text("Encrypted backups can also include saved passwords, Wi-Fi settings, website history, Health data, and call history. Keep the backup password safe; it is required to restore the backup.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isEnabling {
                Text("Enabling backup encryption… Confirm on your device if asked.")
                    .foregroundStyle(.secondary)
            } else if status == .unknown {
                HStack {
                    Text("无法读取加密状态，请解锁设备后重试。")
                        .foregroundStyle(.orange)
                    Button("重试") { updateDeviceStatus() }
                        .disabled(isReadingStatus)
                }
            }
        }
        .onReceive(timer) { _ in
            if status != .finding { updateDeviceStatus() }
        }
        .sheet(isPresented: $showPasswordSheet, onDismiss: {
            password = ""
            confirmation = ""
        }) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Set Backup Password")
                    .font(.title3)
                    .bold()
                Text("Backup password is required to restore an encrypted backup. Please keep it safe.")
                    .foregroundStyle(.secondary)
                SecureField("New Password", text: $password)
                SecureField("Confirm Password", text: $confirmation)
                if !confirmation.isEmpty && password != confirmation {
                    Text("Passwords do not match.")
                        .foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { closePasswordSheet() }
                    Button("Enable Encryption") {
                        let newPassword = password
                        closePasswordSheet()
                        enableEncryption(with: newPassword)
                    }
                    .disabled(password.isEmpty || password != confirmation)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 420)
        }
        .alert("Could not enable backup encryption. Check the device and try again.", isPresented: $showEnableError) {
            Button("OK", role: .cancel) {}
        }
    }

    private func closePasswordSheet() {
        showPasswordSheet = false
        password = ""
        confirmation = ""
    }

    private func enableEncryption(with password: String) {
        guard let udid = vm.deviceIdentifier else { return }
        isEnabling = true
        DispatchQueue.global(qos: .userInitiated).async {
            AuxiliaryExecute.spawn(
                command: MobileBackupTask.mobileBackupExecutable,
                args: ["-u", udid, "encryption", "on"],
                environment: ["BACKUP_PASSWORD": password],
                timeout: 180
            )
            var enabled: Bool?
            for attempt in 0..<5 {
                enabled = Self.readDeviceStatus(udid: udid)
                if enabled == true { break }
                if attempt < 4 { Thread.sleep(forTimeInterval: 1) }
            }
            DispatchQueue.main.async {
                isEnabling = false
                status = enabled.map { $0 ? .enabled : .disabled } ?? .unknown
                vm.backupEncrypted = enabled ?? false
                if enabled != true {
                    showEnableError = true
                }
            }
        }
    }

    private func updateDeviceStatus() {
        guard !isEnabling, !isReadingStatus, let udid = vm.deviceIdentifier else { return }
        isReadingStatus = true
        DispatchQueue.global(qos: .utility).async {
            let enabled = Self.readDeviceStatus(udid: udid)
            DispatchQueue.main.async {
                isReadingStatus = false
                guard !isEnabling, vm.deviceIdentifier == udid else { return }
                status = enabled.map { $0 ? .enabled : .disabled } ?? .unknown
                vm.backupEncrypted = enabled ?? false
            }
        }
    }

    static func readDeviceStatus(udid: String) -> Bool? {
        AppleMobileDeviceManager.shared.readBackupEncryptionStatus(udid: udid)
    }
}
