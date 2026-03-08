//
//  PrepareBackupView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import SwiftUI

struct PrepareBackupView: View {
    @Environment(ViewModel.self) var vm

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                Text("Prepare Backup")
                    .font(.title2)
                    .bold()
                Text("Please scroll down and check each item carefully")
                    .multilineTextAlignment(.center)

                BackupLocationView()

                if vm.showAppPackageDownloadPanel {
                    BackupApplicationView()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                BackupEncryptionIndicatorView()

                Button {
                    vm.page = .backupProgress
                } label: {
                    CardContentView {
                        Text("Start Backup")
                            .foregroundStyle(.accent)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.plain)

                Spacer().frame(height: 128)
            }
        }
        .animation(.spring, value: vm.showAppPackageDownloadPanel)
        .frame(maxWidth: 650)
        .padding(.horizontal, 32)
    }
}
