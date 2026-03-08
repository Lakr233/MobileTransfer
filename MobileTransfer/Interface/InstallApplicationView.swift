//
//  InstallApplicationView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/26.
//

import SwiftUI

struct InstallApplicationView: View {
    @Environment(ViewModel.self) var vm

    @State var openPreRestore = false

    var body: some View {
        VStack(spacing: 16) {
            if let ivm = vm.applicationInstallTask {
                InstallApplicationTaskView(task: ivm)
                    .transition(.opacity)

                if ivm.completed {
                    nextButton
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
        .onAppear { vm.createApplicationInstallTask() }
        .padding(.bottom, 16)
    }

    var cancelButton: some View {
        Button {
            guard let window = NSApp.mainWindow else { return }

            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Cancel Install", comment: "")
            alert.informativeText = NSLocalizedString("Are you sure you want to stop install?", comment: "")
            alert.addButton(withTitle: NSLocalizedString("Stop", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("Continue", comment: ""))
            alert.alertStyle = .warning
            alert.buttons.first?.hasDestructiveAction = true
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    assert(vm.applicationInstallTask != nil)
                    vm.applicationInstallTask?.terminate()
                    vm.applicationInstallTask = nil
                    vm.page = .welcome
                }
            }
        } label: {
            CardContentView {
                Text("Stop Install")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
    }

    var nextButton: some View {
        Button {
            openPreRestore = true
        } label: {
            CardContentView {
                Text("Next")
                    .foregroundStyle(.accent)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $openPreRestore) {
            MergeRestoreCheckView {
                vm.page = .restoreProgress
            } onCancel: {
                vm.page = .prepareRestore
            }
        }
    }
}
