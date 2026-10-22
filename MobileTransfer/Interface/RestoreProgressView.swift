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
                Spacer(minLength: 0)
                if rvm.completed {
                    TransferResultView(title: rvm.success ? "恢复数据已传送完成" : "恢复未完成",
                                       message: rvm.success ? "设备正在重新启动，请保持连接，并在手机上完成后续设置。" : failureMessage(rvm),
                                       success: rvm.success) {
                        vm.restoreTask = nil
                        vm.restorePassword = ""
                        vm.page = .welcome
                    }
                } else {
                    RestoreTaskView(task: rvm)
                    cancelButton
                }
                Spacer(minLength: 0)
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

    private func failureMessage(_ task: RestoreTask) -> String {
        let errors = task.restoreDeviceTask.output.map(\.text).filter {
            $0.localizedCaseInsensitiveContains("error") || $0.localizedCaseInsensitiveContains("failed")
        }
        return errors.isEmpty ? "恢复工具未能完成操作，请检查设备提示和连接后重试。" : Array(Set(errors)).sorted().joined(separator: "\n")
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
            Text("Stop Restore")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}
