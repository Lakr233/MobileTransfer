//
//  RestoreModeInfoView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/10/3.
//

import SwiftUI

struct RestoreModeInfoView: View {
    @Environment(ViewModel.self) var vm

    var body: some View {
        MessageBoxView(title: "Restore Mode", width: 666) {
            Text("There are two types of restore modes, **Merge Restore** and **Replace Restore**.")

            Divider()
            HStack {
                Text(String(88))
                    .hidden()
                    .overlay {
                        Image(systemName: "arrow.right.and.line.vertical.and.arrow.left")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .bold()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                Text("Merge Restore")
                    .bold()
                Spacer()
            }
            .foregroundStyle(vm.restoreMode == .merge || vm.restoreMode == .mergeWithoutInstallApplication ? .accent : .primary)

            Text("System data (photos, music, messages...) will be merged.")
            Text("App data will be replaced if exists in backup.")
            Text("App data will be discard if the app was not installed.")
                .underline(vm.restoreLocation == nil)

            Divider()
            HStack {
                Text(String(88))
                    .hidden()
                    .overlay {
                        Image(systemName: "eraser.line.dashed")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .bold()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                Text("Replace Restore")
                    .bold()
                Spacer()
            }
            .foregroundStyle(vm.restoreMode == .replace ? .accent : .primary)

            Text("All data on the device will be erased. All data exists in backup will be restored.")
            Text("After reboot, you may need to enter the original device password to decrypt backup.")
            Text("You cannot install apps comes within the backup.")
                .underline(vm.restoreLocation == nil)

            if vm.restoreLocation != nil {
                if vm.restoreApplicationsCount == 0 {
                    Divider()
                    Text("This backup does not include any apps, we suggest you to choose **Replace Restore**.")
                        .underline()
                } else {
                    Divider()
                    Text("This backup includes \(vm.restoreApplicationsCount) apps, which can not be installed if using Replace Restore.")
                    Text("Therefor, we suggest you to choose **Merge Restore**.")
                        .underline()
                }
            }
        }
    }
}
