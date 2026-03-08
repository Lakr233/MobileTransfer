//
//  BackupProgressView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import SwiftUI

struct BackupProgressView: View {
    @Environment(ViewModel.self) var vm

    var hint: LocalizedStringKey {
        if let tvm = vm.backupTask {
            switch tvm.verificationStatus {
            case .failed:
                return "Failed to verify this backup, please use with caution."
            case .passed:
                return "Archive Verified"
            case .pending:
                return "Verifying Archive..."
            }
        }
        return ""
    }

    var body: some View {
        VStack(spacing: 16) {
            if let tvm = vm.backupTask {
                BackupTaskView(task: tvm)
                    .transition(.opacity)

                if tvm.completed {
                    showInFinder
                    Text(hint)
                        .contentTransition(.numericText())
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .foregroundColor(tvm.verificationStatus == .failed ? .red : .accent)
                        .underline(tvm.verificationStatus == .failed)
                        .onChange(of: tvm.verificationStatus) { _, newValue in
                            if newValue == .failed {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    let info = Archives.validateRestoreArchive(at: tvm.parameter.backupLocation)
                                    assert(!info.verified)
                                    Archives.presentArchiveBroken(info: info)
                                }
                            }
                        }
                } else {
                    cancelButton
                }
            } else {
                ProgressView()
                    .transition(.opacity)
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .animation(.spring, value: vm.backupTask?.verificationStatus)
        .animation(.spring, value: vm.backupTask?.completed)
        .onAppear { vm.createBackupTask() }
        .onAppear { presentPasswordAlert() }
        .padding(.bottom, 16)
    }

    var cancelButton: some View {
        Button {
            guard let window = NSApp.mainWindow else { return }
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Cancel Backup", comment: "")
            alert.informativeText = NSLocalizedString("Are you sure you want to cancel the backup?", comment: "")
            alert.addButton(withTitle: NSLocalizedString("Stop Backup", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("Continue", comment: ""))
            alert.alertStyle = .warning
            alert.buttons.first?.hasDestructiveAction = true
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    assert(vm.backupTask != nil)
                    vm.backupTask?.terminate()
                    vm.backupTask = nil
                    vm.page = .welcome
                }
            }
        } label: {
            CardContentView {
                Text("Stop Backup")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
    }

    var showInFinder: some View {
        Button {
            vm.showBackupLocationInFinder()
        } label: {
            CardContentView {
                Text("Show In Finder")
                    .foregroundStyle(.accent)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
    }

    func presentPasswordAlert() {
        guard let progress = vm.backupTask?.deviceDataTask.overall,
              progress.fractionCompleted == 0
        else { return }
        guard let window = NSApp.mainWindow else { return }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Backup Requested", comment: "")
        alert.informativeText = NSLocalizedString("Please enter the password on the device if needed", comment: "")
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))

        alert.beginSheetModal(for: window)
    }
}
