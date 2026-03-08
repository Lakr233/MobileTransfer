//
//  MergeRestoreCheckView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/10/3.
//

import SwiftUI

struct MergeRestoreCheckView: View {
    @Environment(ViewModel.self) var vm

    typealias ExecutionBlock = () -> Void
    let onConfirm: ExecutionBlock?
    let onCancel: ExecutionBlock?

    init(onConfirm: ExecutionBlock? = nil, onCancel: ExecutionBlock? = nil) {
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    @Environment(\.dismiss) var dismiss

    @State var checking = true

    struct AppName: Identifiable, Equatable {
        var id: UUID = .init()

        var name: String
        var bundleIdentifier: String
        var installed: Bool
    }

    @State var missingApps = [AppName]()

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            HStack {
                Text("Merge Restore - Preflight Check").bold()
                Spacer()
            }
            .padding(16)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                content.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            Divider()
            HStack {
                Button("Cancel") {
                    dismiss()
                    onCancel?()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Continue to Restore") {
                    dismiss()
                    onConfirm?()
                }
                .keyboardShortcut(.defaultAction)
            }
            .disabled(checking)
            .padding(16)
        }
        .frame(width: 600)
        .onAppear { scan() }
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if checking {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Checking software installation info...")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                if missingApps.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        Text("You have installed all apps required to restore this backup.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Some of the app required by this backup is not yet installed. By continue, the data of these apps will be lost.")
                        Divider()
                        notInstalledAppList
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            Divider()
            Text("If installed app does not open, sign in to App Store with corresponding Apple ID to activate them.")
                .underline()
        }
        .animation(.spring, value: checking)
        .animation(.spring, value: missingApps)
        .frame(height: 250)
    }

    var notInstalledAppList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                ForEach(missingApps) { app in
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name)
                                .lineLimit(1)
                                .bold()
                            Text(app.bundleIdentifier)
                                .lineLimit(1)
                        }
                        Spacer()
                        if app.installed {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }

    func scan() {
        checking = true
        DispatchQueue.global().async {
            let missing = scanEx()
            DispatchQueue.main.async {
                missingApps = missing
                checking = false
            }
        }
    }

    func scanEx() -> [AppName] {
        guard let backup = vm.restoreLocation else {
            assertionFailure()
            return []
        }
        let installed = installedApps()

        let infoPlistPath = URL(fileURLWithPath: backup).appendingPathComponent("Info.plist")
        guard let infoData = try? Data(contentsOf: infoPlistPath),
              let infoObject = try? PropertyListSerialization.propertyList(
                  from: infoData,
                  options: [],
                  format: nil
              ) as? [String: Any]
        else {
            assertionFailure()
            return []
        }

        guard let installedApps = infoObject["Installed Applications"] as? [String] else {
            assertionFailure()
            return []
        }

        var missingList = [AppName]()
        for app in installedApps where !installed.contains(app) {
            // now read from Info.plist/Applications/bundleID/iTunesMetadata
            var iTunesMetadata: Any? = infoObject["Applications"] as? [String: [String: Any]]
            iTunesMetadata = (iTunesMetadata as? [String: [String: Any]])?[app]?["iTunesMetadata"]

            guard let data = iTunesMetadata as? Data,
                  let object = try? PropertyListSerialization.propertyList(
                      from: data,
                      options: [],
                      format: nil
                  ) as? [String: Any]
            else {
                missingList.append(.init(name: app, bundleIdentifier: app, installed: false))
                continue
            }

            guard let name = object["itemName"] as? String else {
                missingList.append(.init(name: app, bundleIdentifier: app, installed: false))
                continue
            }

            missingList.append(.init(name: name, bundleIdentifier: app, installed: false))
        }

        return missingList
    }

    func installedApps() -> Set<String> {
        guard let udid = vm.deviceIdentifier else {
            assertionFailure()
            return []
        }
        let apps = AppleMobileDeviceManager.shared.listApplications(udid: udid, connection: .usb) ?? .init()

        var bids: Set<String> = []
        for (bundleIdentifier, _) in apps {
            guard !bundleIdentifier.isEmpty else {
                print("[?] failed to parse \(bundleIdentifier)")
                continue
            }
            bids.insert(bundleIdentifier)
        }
        return bids
    }
}
