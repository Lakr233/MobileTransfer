//
//  PrepareRestoreView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import SwiftUI

struct PrepareRestoreView: View {
    @Environment(ViewModel.self) var vm

    var restorable: Bool {
        [
            vm.restoreLocation != nil,
            !vm.restoreArchiveIsPasswordProtected
                || !vm.restorePassword.isEmpty,
            vm.restoreMode != .unspecified,
        ].allSatisfy(\.self)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                Text("Prepare Restore")
                    .font(.title2)
                    .bold()

                RestoreArchivePickerView()

                if vm.restoreArchiveIsPasswordProtected {
                    HStack(alignment: .top, spacing: 16) {
                        RestoreModePickerView()
                            .frame(maxWidth: .infinity)
                        RestorePasswordView()
                            .frame(maxWidth: .infinity)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    RestoreModePickerView()
                        .frame(maxWidth: .infinity)
                        .transition(
                            .opacity.combined(with: .scale(scale: 0.95))
                        )
                }

                Button {
                    start()
                } label: {
                    CardContentView {
                        Text("Start Restore")
                            .foregroundStyle(.accent)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.plain)
                .opacity(restorable ? 1 : 0.5)
                .disabled(!restorable)

                Spacer().frame(height: 128)
            }
        }
        .animation(.spring, value: vm.restoreLocation)
        .animation(.spring, value: vm.restorePassword)
        .animation(.spring, value: vm.restoreArchiveIsPasswordProtected)
        .animation(.spring, value: vm.restoreMode)
        .frame(maxWidth: 650)
        .padding(.horizontal, 32)
        .sheet(isPresented: $openMergeRestoreCheck) {
            MergeRestoreCheckView(onConfirm: {
                vm.page = .restoreProgress
            })
        }
    }

    @State var overrideActivationCheck = false
    @State var overrideSystemVersionCheck = false
    @State var openMergeRestoreCheck = false

    func start() {
        guard let window = NSApp.mainWindow else { return }

        guard checkIfBackupVersionMatchesRequirements() || overrideSystemVersionCheck else {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString(
                "iOS Version Too Old",
                comment: ""
            )
            alert.informativeText = NSLocalizedString(
                "The backup was created on a newer version of iOS. Please update the device to the latest version before restoring.",
                comment: ""
            )
            alert.addButton(withTitle: NSLocalizedString("Continue Anyway (Ignore Error)", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("Continue Anyway (Modify Backup)", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("Upgrade with Finder", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("Abort", comment: ""))
            alert.buttons[0].hasDestructiveAction = true
            alert.buttons[1].hasDestructiveAction = true
            alert.alertStyle = .critical
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    overrideSystemVersionCheck = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        start()
                    }
                } else if response == .alertSecondButtonReturn {
                    replaceBackupManifestWithCurrentSystemVersion()
                } else if response == .alertSecondButtonReturn {
                    // just open Finder
                    NSWorkspace.shared.openApplication(
                        at: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
                        configuration: .init()
                    )
                }
            }
            return
        }

        guard !checkIfDeviceIsFindMyEnabled() else {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString(
                "Find My Enabled",
                comment: ""
            )
            alert.informativeText = NSLocalizedString(
                "Please disable Find My before restoring.",
                comment: ""
            )
            alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
            alert.buttons.first?.hasDestructiveAction = true
            alert.alertStyle = .critical
            alert.beginSheetModal(for: window)
            return
        }

        guard checkIfDeviceIsActivated() || overrideActivationCheck else {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString(
                "Device Not Activated",
                comment: ""
            )
            alert.informativeText = NSLocalizedString(
                "Please activate the device before restoring. If you are on setup, continue the process and get back when pass the activation screen.",
                comment: ""
            )
            alert.addButton(withTitle: NSLocalizedString("Continue Anyway", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
            alert.buttons.first?.hasDestructiveAction = true
            alert.alertStyle = .critical
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    overrideActivationCheck = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        start()
                    }
                }
            }
            return
        }

        switch vm.restoreMode {
        case .unspecified:
            assertionFailure()
            return
        case .replace:
            popEraseConfirm()
        case .merge:
            if vm.restoreApplicationsCount == 0 {
                openMergeRestoreCheck = true
            } else {
                vm.page = .installApplication
            }
        case .mergeWithoutInstallApplication:
            openMergeRestoreCheck = true
        }
    }

    func checkIfDeviceIsActivated() -> Bool {
        guard let udid = vm.deviceIdentifier else { return false }
        let device = AppleMobileDeviceManager.shared.obtainDeviceInfo(
            udid: udid,
            domain: nil,
            key: nil,
            connection: .usb
        )
        guard let device else { return false }
        guard let activationStatus = device.activationState else {
            return false
        }
        return
            activationStatus
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                != "Unactivated".lowercased()
    }

    func checkIfDeviceIsFindMyEnabled() -> Bool {
        guard let udid = vm.deviceIdentifier else { return false }
        let device = AppleMobileDeviceManager.shared.obtainDeviceInfo(
            udid: udid,
            domain: "com.apple.fmip",
            key: "IsAssociated",
            connection: .usb
        )
        guard let device else { return false }
        return device.store.value as? Bool ?? false
    }

    func checkIfBackupVersionMatchesRequirements() -> Bool {
        guard let udid = vm.deviceIdentifier else {
            assertionFailure()
            return false
        }
        var backupVersion = vm.restoreArchiveSystemBuildVersion
        let query = AppleMobileDeviceManager.shared.obtainDeviceInfo(
            udid: udid,
            connection: .usb
        )
        guard var deviceVersion = query?.buildVersion else {
            return false
        }
        if deviceVersion.count < backupVersion.count {
            deviceVersion += String(repeating: "0", count: backupVersion.count - deviceVersion.count)
        } else if deviceVersion.count > backupVersion.count {
            backupVersion += String(repeating: "0", count: deviceVersion.count - backupVersion.count)
        }
        assert(deviceVersion.count == backupVersion.count)
        return deviceVersion.lowercased() >= backupVersion.lowercased()
    }

    func replaceBackupManifestWithCurrentSystemVersion() {
        guard let udid = vm.deviceIdentifier else { return }
        guard let window = NSApp.mainWindow else { return }

        let query = AppleMobileDeviceManager.shared.obtainDeviceInfo(
            udid: udid,
            connection: .usb
        )
        guard let deviceProductVersion = query?.productVersion,
              let deviceBuildVersion = query?.buildVersion
        else {
            assertionFailure()
            return
        }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString(
            "Modify Backup Manifest",
            comment: ""
        )
        alert.informativeText = String(
            format: NSLocalizedString(
                "The backup manifest created by %@ will be modified to match the current device system version %@ (%@). This may cause issues during restore. Please proceed with caution.",
                comment: ""
            ),
            vm.restoreArchiveSystemBuildVersion,
            deviceProductVersion,
            deviceBuildVersion
        )
        alert.addButton(withTitle: NSLocalizedString("Modify", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.buttons.first?.hasDestructiveAction = true
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window) { response in
            if response != .alertFirstButtonReturn { return }

            do {
                let backup = try URL(fileURLWithPath: vm.restoreLocation.get())

                do {
                    let manifestPath = backup
                        .appendingPathComponent("Manifest")
                        .appendingPathExtension("plist")
                    let dic = try PropertyListSerialization.propertyList(
                        from: Data(contentsOf: manifestPath),
                        options: [],
                        format: nil
                    )
                    var manifest = try (dic as? [String: Any]).get()
                    var lockdown = try (manifest["Lockdown"] as? [String: Any]).get()
                    _ = try (lockdown["ProductVersion"] as? String).get()
                    _ = try (lockdown["BuildVersion"] as? String).get()
                    lockdown["ProductVersion"] = deviceProductVersion
                    lockdown["BuildVersion"] = deviceBuildVersion
                    manifest["Lockdown"] = lockdown
                    let newData = try PropertyListSerialization.data(
                        fromPropertyList: manifest,
                        format: .xml,
                        options: 0
                    )
                    try newData.write(to: manifestPath)
                }

                do {
                    let infoPath = backup
                        .appendingPathComponent("Info")
                        .appendingPathExtension("plist")
                    let dic = try PropertyListSerialization.propertyList(
                        from: Data(contentsOf: infoPath),
                        options: [],
                        format: nil
                    )
                    var info = try (dic as? [String: Any]).get()
                    _ = try (info["Product Version"] as? String).get()
                    _ = try (info["Build Version"] as? String).get()
                    info["Product Version"] = deviceProductVersion
                    info["Build Version"] = deviceBuildVersion
                    let newData = try PropertyListSerialization.data(
                        fromPropertyList: info,
                        format: .xml,
                        options: 0
                    )
                    try newData.write(to: infoPath)
                }
                guard vm.validateRestoreArchive(at: backup) else {
                    throw NSError(
                        domain: "Error",
                        code: -1,
                        userInfo: [
                            NSLocalizedDescriptionKey: NSLocalizedString(
                                "The backup archive is corrupted after modification.",
                                comment: ""
                            ),
                        ]
                    )
                }
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Success", comment: "")
                alert.informativeText = NSLocalizedString(
                    "The backup manifest has been modified successfully.",
                    comment: ""
                )
                alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
                alert.alertStyle = .informational
                alert.beginSheetModal(for: window)
            } catch {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Error", comment: "")
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
                alert.alertStyle = .critical
                alert.beginSheetModal(for: window)
            }
        }
    }

    func popEraseConfirm() {
        guard let window = NSApp.mainWindow else { return }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Erase Device", comment: "")
        alert.informativeText = NSLocalizedString(
            "The device will be erased when restoring.", comment: ""
        )
        alert.addButton(
            withTitle: NSLocalizedString("Erase & Restore", comment: "")
        )
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.buttons.first?.hasDestructiveAction = true
        alert.alertStyle = .critical
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                vm.page = .restoreProgress
            }
        }
    }
}
