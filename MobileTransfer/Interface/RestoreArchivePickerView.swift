//
//  RestoreArchivePickerView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/26.
//

import SwiftUI

struct RestoreArchivePickerView: View {
    @Environment(ViewModel.self) private var vm
    @State private var backups: [Archives.BackupRecord] = []
    @State private var loading = true
    @State private var checkingPath: String?

    var onCheckingChange: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("选择备份").font(.headline)
            HStack {
                Menu {
                    ForEach(backups) { backup in
                        Button("\(backup.displayName) · \(backup.date.formatted(date: .abbreviated, time: .shortened))") { select(backup) }
                    }
                } label: {
                    Text(selectedDescription).lineLimit(2)
                }
                .disabled(loading || checkingPath != nil || backups.isEmpty)
                if loading || checkingPath != nil { ProgressView().controlSize(.small) }
                Button("从文件选择…") { vm.pickRestoreArchive() }.disabled(checkingPath != nil)
            }
            if let path = vm.restoreLocation {
                Text(path).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
            }
        }
        .onAppear(perform: loadHistory)
        .onChange(of: vm.restoreLocation) { loadHistory() }
        .onChange(of: checkingPath) { onCheckingChange(checkingPath != nil) }
    }

    private var selectedDescription: String {
        if let record = backups.first(where: { $0.url.path == vm.restoreLocation }) {
            return "\(record.displayName) · \(record.date.formatted(date: .abbreviated, time: .shortened))"
        }
        return vm.restoreLocation.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "选择备份…"
    }

    private func loadHistory() {
        guard let deviceIdentifier = vm.deviceIdentifier else { return }
        loading = true
        DispatchQueue.global(qos: .utility).async {
            let result = Archives.availableBackups(for: deviceIdentifier)
            DispatchQueue.main.async {
                backups = result
                loading = false
            }
        }
    }

    private func select(_ backup: Archives.BackupRecord) {
        checkingPath = backup.id
        DispatchQueue.global(qos: .userInitiated).async {
            let info = Archives.validateRestoreArchive(at: backup.url)
            DispatchQueue.main.async {
                checkingPath = nil
                guard info.verified else {
                    Archives.presentArchiveBroken(info: info)
                    return
                }
                vm.restorePassword = ""
                vm.restoreLocation = backup.url.path
                vm.restoreArchiveIsPasswordProtected = info.isEncrypted
                vm.restoreApplicationsCount = info.applications
                vm.restoreArchiveSystemBuildVersion = info.systemBuildVersion
                Archives.rememberCompletedBackup(at: backup.url)
            }
        }
    }
}
