//
//  BackupLocationView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import SwiftUI

struct BackupLocationView: View {
    @Environment(ViewModel.self) var vm

    var locationDescription: LocalizedStringKey {
        let value = try? FileManager.default.attributesOfFileSystem(
            forPath: vm.backupLocation
        )[.systemFreeSize] as? Int64
        guard let value else {
            return "Unable to check free space"
        }
        let fmt = ByteCountFormatter()
        fmt.allowedUnits = .useAll
        fmt.countStyle = .file
        return "Free space: \(fmt.string(fromByteCount: value))"
    }

    var body: some View {
        CardContentView {
            CardContentHeader(icon: "archivebox", title: "Storage Location") {}
            Text("Please choose a backup storage location. Make sure this location is safe and has fast read and write speeds.")
            Divider()
            Text(vm.backupLocation)
                .foregroundStyle(.secondary)
            Divider()
            HStack {
                Button("Choose") { vm.pickSaveLocation() }
                Button("Show In Finder") { vm.showBackupLocationInFinder() }
                Spacer()
                Text(locationDescription)
                    .foregroundStyle(.secondary)
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
