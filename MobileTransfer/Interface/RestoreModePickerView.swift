//
//  RestoreModePickerView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/10/3.
//

import SwiftUI

struct RestoreModePickerView: View {
    @Environment(ViewModel.self) var vm

    @State var openInfo = false

    let inset: CGFloat = 4

    var hint: LocalizedStringKey {
        switch vm.restoreMode {
        case .unspecified:
            "Select a restore mode to proceed."
        case .replace:
            "Will erase your device and restore the backup."
        case .merge:
            if vm.restoreApplicationsCount > 0 {
                "Will install apps and restore backup."
            } else {
                "Will restore backup and merge with existing data on device."
            }
        case .mergeWithoutInstallApplication:
            "Will restore backup and merge with existing data on device."
        }
    }

    var body: some View {
        @Bindable var vm = vm
        CardContentView {
            CardContentHeader(icon: "document.badge.gearshape", title: "Restore Mode") {
                if vm.restoreMode == .unspecified {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .transition(.opacity.combined(with: .scale))
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .transition(.opacity.combined(with: .scale))
                }
            }

            Text(hint)
                .contentTransition(.numericText())

            Text(String("888"))
                .frame(maxWidth: .infinity)
                .hidden()
                .overlay {
                    Picker("Restore Mode", selection: $vm.restoreMode) {
                        let buildView = { (mode: ViewModel.RestoreMode) in
                            if mode == .mergeWithoutInstallApplication, vm.restoreApplicationsCount == 0
                            { return AnyView(EmptyView()) }
                            if mode == .unspecified { return AnyView(EmptyView()) }
                            return AnyView(Text(mode.title))
                        }
                        ForEach(ViewModel.RestoreMode.allCases, id: \.self) { mode in
                            buildView(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .onAppear {
                        vm.restoreMode = vm.restoreApplicationsCount > 0 ? .merge : .replace
                    }
                }

            Button {
                openInfo = true
            } label: {
                Text("Need help?")
                    .underline()
                    .foregroundStyle(.accent)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $openInfo) {
                RestoreModeInfoView()
            }
        }
        .animation(.spring, value: vm.restoreMode)
    }
}

extension ViewModel.RestoreMode {
    var title: LocalizedStringKey {
        switch self {
        case .unspecified:
            "Select..."
        case .replace:
            "Replace"
        case .merge:
            "Merge"
        case .mergeWithoutInstallApplication:
            "Merge (Without Install Application)"
        }
    }
}
