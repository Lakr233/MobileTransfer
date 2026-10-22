//
//  BackupProgressView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import SwiftUI

struct BackupProgressView: View {
    @Environment(ViewModel.self) var vm

    var body: some View {
        VStack(spacing: 16) {
            if let tvm = vm.backupTask {
                Spacer(minLength: 0)
                if tvm.completed && tvm.deviceDataTask.success {
                    resultContent(tvm)
                } else {
                    BackupTaskView(task: tvm)
                        .transition(.opacity)
                    if tvm.isCancelling {
                        ProgressView("正在停止并清理未完成的备份…")
                    } else if tvm.completed {
                        doneButton
                    } else {
                        cancelButton
                    }
                }
                Spacer(minLength: 0)
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
        .padding(.bottom, 16)
    }

    private func resultContent(_ task: BackupTask) -> some View {
        VStack(spacing: 24) {
            switch task.verificationStatus {
            case .pending:
                ProgressView()
                Text("正在完成备份…").font(.title2.weight(.semibold))
            case .passed:
                if let apps = task.applicationDataTask, !apps.failedTasks.isEmpty {
                    TransferResultView(title: "设备数据已备份", message: "有 \(apps.failedTasks.count) 个 App 安装包未下载成功，请检查下载结果。", success: false, onDone: finish)
                } else {
                    TransferResultView(title: "备份完成", onDone: finish)
                }
            case .failed:
                TransferResultView(title: "备份校验未通过", message: "无法确认备份完整，请重新备份。", success: false, onDone: finish)
            }
        }
        .padding(32)
        .frame(maxWidth: 560)
    }

    private var doneButton: some View {
        Button("完成", action: finish)
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
    }

    private func finish() {
        vm.backupTask = nil
        vm.page = .welcome
    }

    var cancelButton: some View {
        Button {
            guard let window = NSApp.mainWindow else { return }
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Cancel Backup", comment: "")
            alert.informativeText = "停止后，本次新建的未完成备份将移到废纸篓。已有备份的续传或重试文件会保留。"
            alert.addButton(withTitle: NSLocalizedString("Stop Backup", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("Continue", comment: ""))
            alert.alertStyle = .warning
            alert.buttons.first?.hasDestructiveAction = true
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    assert(vm.backupTask != nil)
                    vm.backupTask?.cancelAndCleanUp { error in
                        if let error { NSAlert(error: error).beginSheetModal(for: window) }
                        vm.backupTask = nil
                        vm.page = .welcome
                    }
                }
            }
        } label: {
            Text("Stop Backup")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(vm.backupTask?.isCancelling == true)
    }

}
