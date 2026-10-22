//
//  MobileTransfer+Commands.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/10/23.
//

import SwiftUI

extension MobileTransfer {
    @CommandsBuilder
    var commands: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandMenu("Archives") {
            Button("Verify Archive...") {
                Archives.beginVerification()
            }
            Divider()
            Button("Convert from BBackupp...") {
                Archives.convertFromBBackupp()
            }
            Button("What is BBackupp?") {
                NSWorkspace.shared.open(URL(string: "https://github.com/Lakr233/BBackupp")!)
            }
            if vm.page == .prepareBackup {
                Divider()
                Button("Load Checkpoint...") {
                    progress = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        Archives.migrateTo(location: URL(fileURLWithPath: vm.backupLocation)) { result in
                            progress = false
                            if case let .failure(error) = result {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    let alert = NSAlert()
                                    alert.messageText = NSLocalizedString("Failed to Load", comment: "")
                                    alert.informativeText = error.localizedDescription
                                    if let window = NSApp.windows.first {
                                        alert.beginSheetModal(for: window)
                                    } else {
                                        alert.runModal()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
