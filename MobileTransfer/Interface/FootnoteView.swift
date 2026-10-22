//
//  FootnoteView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import SwiftUI

struct FootnoteView: View {
    @Environment(ViewModel.self) var vm

    var version: String {
        "v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")"
    }

    var showBackButton: Bool {
        if vm.navigationArray.isEmpty { return false }
        if !vm.page.showBackButton { return false }
        return true
    }

    var body: some View {
        HStack(spacing: 16) {
            Button {
                vm.navigationArray.removeFirst()
            } label: {
                Image(systemName: "arrow.left")
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(showBackButton ? 1 : 0)
            .frame(width: 100, alignment: .leading)
            if vm.taskCompleted {
                Button {
                    vm.page = .welcome
                } label: {
                    Text("Back")
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if vm.page == .welcome || vm.page == .actionMenu {
                Text("iOS TimeMachine")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .contentTransition(.numericText())
            } else {
                Spacer()
            }
            Text(version)
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
                .contentTransition(.numericText())
                .opacity(vm.page == .welcome || vm.page == .actionMenu ? 1 : 0)
                .frame(width: 100, alignment: .trailing)
        }
        .animation(.spring, value: vm.page)
        .font(.body)
        .onChange(of: showBackButton) { _, newValue in
            if !newValue {
                while vm.navigationArray.count > 1 {
                    vm.navigationArray.removeLast()
                }
            }
        }
    }
}

private extension ViewModel.Page {
    var showBackButton: Bool {
        switch self {
        case .welcome:
            false
        case .actionMenu:
            true
        case .findDevice:
            true
        case .prepareBackup, .prepareRestore:
            true
        case .backupProgress, .restoreProgress:
            false
        case .installApplication:
            false
        }
    }
}
