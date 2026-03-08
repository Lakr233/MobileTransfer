//
//  BackupApplicationView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import ApplePackage
import SwiftUI

struct BackupApplicationView: View {
    @Environment(ViewModel.self) var vm

    @State var isScaning: Bool = false
    @State var avm = AppStoreBackend.shared

    @State var appList: [App] = []
    @State var openSignIn: String? = nil
    @State var openRestoreModeInfo = false

    let timer = Timer
        .publish(every: 5, on: .main, in: .common)
        .autoconnect()

    @State var extraAccount: Set<String> = []

    var accounts: [String] {
        Array(Set(
            []
                + appList.map(\.account).filter { $0 != "*" }
                + Array(extraAccount)
        )).sorted()
    }

    var allSignedIn: Bool {
        accounts.allSatisfy { avm.accounts.map(\.email).contains($0) }
    }

    var unableToGetAccountCount: Int {
        appList.count(where: { $0.account == "*" })
    }

    var desc: LocalizedStringKey {
        if unableToGetAccountCount > 0 {
            "This device has \(appList.count) apps installed, \(unableToGetAccountCount) of them is unable to get account information, will use first eligible account to download."
        } else {
            "This device has \(appList.count) applications installed"
        }
    }

    var body: some View {
        @Bindable var vm = vm
        CardContentView {
            CardContentHeader(icon: "arrow.down.circle", title: "Backup Applications") {
                if vm.backupApps {
                    if allSignedIn {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                } else {
                    Image(systemName: "circle.dashed")
                }
            }
            .animation(.spring, value: avm.accounts)
            .animation(.spring, value: vm.backupApps)
            Text("Backups do not include applications themselves. If you need to automatically download during backup and install during recovery, please log in to the corresponding app store account here. Only App Store apps are supported, TestFlight or in-house apps are ignored.")
            Button {
                openRestoreModeInfo = true
            } label: {
                Text("Only Merge Restore can be used to install applications downloaded here.")
                    .foregroundStyle(.accent)
                    .underline()
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $openRestoreModeInfo) {
                RestoreModeInfoView()
            }
            Divider()
            if isScaning {
                ProgressView()
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.opacity.combined(with: .scale))
            } else {
                if accounts.isEmpty {
                    Text("No App Store account found")
                } else {
                    ForEach(accounts, id: \.self) { account in
                        HStack {
                            Image(systemName: "smallcircle.filled.circle")
                            Text(account)
                                .strikethrough(!vm.backupApps)
                            Spacer()
                            if avm.accounts.map(\.email).contains(account) {
                                Button {
                                    avm.delete(email: account)
                                    extraAccount.remove(account)
                                } label: {
                                    Text("Sign Out")
                                        .foregroundStyle(.red)
                                }
                            } else {
                                Button {
                                    openSignIn = account
                                } label: {
                                    Text("Sign In")
                                        .foregroundStyle(.accent)
                                }
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
            Divider()
            Text(desc)
                .contentTransition(.numericText())
            HStack {
                Toggle("Enable", isOn: $vm.backupApps)
                Spacer()
                Button {
                    openSignIn = ""
                } label: {
                    Text("Add Account Manually")
                }
            }
        }
        .onAppear { scanApps(isFirstScan: true) }
        .onReceive(timer) { _ in scanApps() }
        .onChange(of: accounts) { _, newValue in
            vm.backupApplicationAccountAllowed = Set(newValue)
        }
        .sheet(item: $openSignIn) { email in
            AppStoreAccountAddView(email: email) { email in
                guard !accounts.contains(email) else { return }
                extraAccount.insert(email)
            }
        }
    }

    func scanApps(isFirstScan: Bool = false) {
        guard let udid = vm.deviceIdentifier else { return }
        if isFirstScan { isScaning = true }

        DispatchQueue.global().async {
            let apps = AppleMobileDeviceManager.shared.listApplications(udid: udid, connection: .usb) ?? .init()

            var appList: [App] = []
            for (bundleIdentifier, value) in apps {
                guard !bundleIdentifier.isEmpty,
                      let value = value.value as? [String: AnyCodable],
                      let iTunesMetadataData = value["iTunesMetadata"]?.value as? Data,
                      let object = try? PropertyListSerialization.propertyList(
                          from: iTunesMetadataData,
                          format: nil
                      ) as? [String: Any]
                else {
                    print("[?] failed to parse \(bundleIdentifier)")
                    continue
                }

                var account: String? = nil

                if account == nil,
                   let downloadInfo = object["com.apple.iTunesStore.downloadInfo"] as? [String: Any],
                   let accountInfo = downloadInfo["accountInfo"] as? [String: Any],
                   let getAccount = accountInfo["AppleID"] as? String,
                   !getAccount.isEmpty
                { account = getAccount }

                if account == nil,
                   let getAccount = object["apple-id"] as? String,
                   !getAccount.isEmpty
                { account = getAccount }

                if account == nil { account = "*" }

                guard let account else { continue }

                let app = App(
                    bundleIdentifier: bundleIdentifier,
                    name: object["itemName"] as? String ?? "",
                    account: account
                )
                appList.append(app)
            }

            DispatchQueue.main.async {
                withAnimation(.spring) {
                    isScaning = false
                    self.appList = appList
                }
                vm.backupApplicationList = appList
            }
        }
    }
}
