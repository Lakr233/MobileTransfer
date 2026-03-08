//
//  RestoreProgressView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/26.
//

import SwiftUI

struct RestoreProgressView: View {
    @Environment(ViewModel.self) var vm

    var body: some View {
        VStack(spacing: 16) {
            if let rvm = vm.restoreTask {
                RestoreTaskView(task: rvm)
                    .transition(.opacity)

                if rvm.completed {
                    EmptyView().onAppear {
                        if rvm.success { presentDeviceRebootingAlert() }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    cancelButton
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            } else {
                ProgressView()
                    .transition(.opacity)
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .animation(.spring, value: vm.restoreTask?.completed)
        .onAppear { vm.createRestoreTask() }
        .padding(.bottom, 16)
    }

    var cancelButton: some View {
        Button {
            guard let window = NSApp.mainWindow else { return }

            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Cancel Restore", comment: "")
            alert.informativeText = NSLocalizedString("Are you sure you want to cancel the restore?", comment: "")
            alert.addButton(withTitle: NSLocalizedString("Stop Restore", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("Continue", comment: ""))
            alert.alertStyle = .warning
            alert.buttons.first?.hasDestructiveAction = true
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    assert(vm.restoreTask != nil)
                    vm.restoreTask?.terminate()
                    vm.restoreTask = nil
                    vm.page = .welcome
                }
            }
        } label: {
            CardContentView {
                Text("Stop Restore")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
    }

    var nextButton: some View {
        Button {
            vm.page = .welcome
        } label: {
            CardContentView {
                Text("Done")
                    .foregroundStyle(.accent)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
    }

    func presentDeviceRebootingAlert() {
        guard let window = NSApp.mainWindow else { return }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Restore Complete", comment: "")
        alert.informativeText = NSLocalizedString("The device is rebooting, please wait for it to finish.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.alertStyle = .informational
        alert.beginSheetModal(for: window)
    }
}
