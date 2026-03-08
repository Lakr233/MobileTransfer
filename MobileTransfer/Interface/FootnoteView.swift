//
//  FootnoteView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import SwiftUI

struct FootnoteView: View {
    @Environment(ViewModel.self) var vm

    @State var openAgreementSheet = false
    @AppStorage("AgreementsShown") var agreementsShown = false

    var showAgreements: Bool {
        vm.mode == .unspecified
    }

    var footnote: LocalizedStringKey {
        if showAgreements {
            return "By using this app you agree to our Terms of Service and Privacy Policy"
        }
        switch vm.mode {
        case .unspecified:
            assertionFailure()
            return ""
        case .backup:
            if let did = vm.deviceIdentifier {
                return "Backup Mode \(did)"
            } else {
                return "Backup Mode"
            }
        case .restore:
            if let did = vm.deviceIdentifier {
                return "Restore Mode \(did)"
            } else {
                return "Restore Mode"
            }
        }
    }

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
                        .foregroundStyle(.accent)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text(footnote)
                    .lineLimit(1)
                    .underline(showAgreements)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .contentTransition(.numericText())
                    .onTapGesture { if showAgreements { openAgreementSheet = true } }
            }
            Text(version)
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
                .contentTransition(.numericText())
                .opacity(vm.page == .actionMenu ? 1 : 0)
                .frame(width: 100, alignment: .trailing)
        }
        .animation(.spring, value: vm.page)
        .animation(.spring, value: vm.mode)
        .animation(.spring, value: vm.deviceIdentifier)
        .font(.body)
        .onChange(of: showBackButton) { _, newValue in
            if !newValue {
                while vm.navigationArray.count > 1 {
                    vm.navigationArray.removeLast()
                }
            }
        }
        .sheet(isPresented: $openAgreementSheet) {
            AgreementSheetView()
        }
        .onAppear { if !agreementsShown {
            openAgreementSheet = true
            agreementsShown = true
        } }
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
