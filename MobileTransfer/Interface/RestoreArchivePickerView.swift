//
//  RestoreArchivePickerView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/26.
//

import SwiftUI

struct RestoreArchivePickerView: View {
    @Environment(ViewModel.self) var vm

    var title: String {
        NSLocalizedString("Please choose a backup to restore.", comment: "")
    }

    var body: some View {
        CardContentView {
            CardContentHeader(icon: "archivebox", title: "Backup Archive") {
                if vm.restoreLocation == nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .transition(.opacity.combined(with: .scale))
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .animation(.spring, value: vm.restoreLocation)
            Text(title)
            Divider()
            Text(vm.restoreLocation ?? NSLocalizedString("Not Selected", comment: ""))
                .foregroundStyle(vm.restoreLocation == nil ? Color.red : .primary)
            Divider()
            HStack {
                Button("Choose") { vm.pickRestoreArchive() }
                Button("Show In Finder") { vm.showRestoreBackupLocationInFinder() }
                    .disabled(vm.restoreLocation == nil)
                Spacer()
            }
            .onAppear {
                try? FileManager.default.createDirectory(
                    atPath: vm.backupLocation,
                    withIntermediateDirectories: true
                )
            }
        }
    }
}
