//
//  ActionMenuView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import SwiftUI

struct ActionMenuView: View {
    @Environment(ViewModel.self) var vm

    var body: some View {
        VStack(spacing: 16) {
            MenuActionButtonView(
                icon: "arrow.right.doc.on.clipboard",
                title: "Backup Device",
                desc: "Download device data and archive to selected destination"
            ) {
                vm.mode = .backup
                vm.page = .findDevice
            }
            MenuActionButtonView(
                icon: "arrow.down.doc",
                title: "Restore Device",
                desc: "Restore device data from selected archive"
            ) {
                vm.mode = .restore
                vm.page = .findDevice
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "cursorarrow.motionlines.click")
                Text("You can also drag backup file here to begin restore.")
            }
        }
        .onAppear { vm.mode = .unspecified }
        .padding()
        .frame(maxWidth: 400)
    }
}

#Preview {
    ActionMenuView()
}

private struct MenuActionButtonView: View {
    let icon: String
    let title: LocalizedStringKey
    let desc: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2)
                        .bold()
                    Text(desc)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.title2)
            }
            .padding()
            .background(.background.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
