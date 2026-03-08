//
//  ContentView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(ViewModel.self) var vm

    let animation: Animation = .interactiveSpring(
        duration: 0.5,
        extraBounce: 0.05,
        blendDuration: 0.25
    )

    var body: some View {
        VStack(spacing: 0) {
            VStack {
                page
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(
                                with: .scale(scale: 0.85, anchor: .center)
                            ),
                            removal: .opacity
                        )
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().padding(.horizontal, -32)
            FootnoteView().padding(.top, 16)
        }
        .animation(animation, value: vm.page)
        .onChange(of: vm.page) {
            if sleepDisabled {
                KeepAwake.disableSleep()
            } else {
                KeepAwake.enableSleep()
            }
        }
        .onOpenURL { openFile($0) }
        .padding(.vertical, 16)
        .padding(.horizontal, 32)
        .background(BackgroundView())
    }

    func openFile(_ item: URL) {
        guard item.pathExtension == "mobiletransfer" else { return }
        guard vm.page == .welcome || vm.page == .actionMenu else { return }
        _ = vm
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            vm.restoreLocation = item.path
            _ = vm.validateRestoreArchive(at: item)
            vm.mode = .restore
            vm.page = .findDevice
        }
    }

    @ViewBuilder
    var page: some View {
        switch vm.page {
        case .welcome:
            WelcomeView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: [.fileURL], isTargeted: nil) { items in
                    guard let item = items.first else { return false }
                    item.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                        guard let data = data as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil)
                        else { return }
                        openFile(url)
                    }
                    return true
                }
        case .actionMenu:
            ActionMenuView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: [.fileURL], isTargeted: nil) { items in
                    guard let item = items.first else { return false }
                    item.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                        guard let data = data as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil)
                        else { return }
                        openFile(url)
                    }
                    return true
                }
        case .findDevice:
            FindDeviceView()
        case .prepareBackup:
            PrepareBackupView()
        case .prepareRestore:
            PrepareRestoreView()
        case .backupProgress:
            BackupProgressView()
        case .restoreProgress:
            RestoreProgressView()
        case .installApplication:
            InstallApplicationView()
        }
    }

    var sleepDisabled: Bool {
        [.findDevice, .restoreProgress, .backupProgress, .installApplication].contains(vm.page)
    }
}
