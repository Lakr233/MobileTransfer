//
//  PrepareBackupView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import AppleMobileDeviceLibrary
import Combine
import ImageIO
import SwiftUI
import SQLite3
import UniformTypeIdentifiers

struct PrepareBackupView: View {
    @Environment(ViewModel.self) var vm
    @Environment(\.scenePhase) private var scenePhase
    @State private var isReadingBattery = false
    @State private var showingRename = false
    @State private var showingBackupContents = false
    @State private var deviceNameDraft = ""
    @State private var renamingDevice = false
    @State private var renameError: String?
    private let batteryTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    var onBusyChange: (Bool) -> Void = { _ in }
    @State private var latestBackup: Archives.BackupRecord?
    @State private var loadingBackupHistory = true
    @State private var checkingRestoreBackup = false
    @State private var encryptionInProgress = false
    @State private var encryptionStatus: BackupEncryptionIndicatorView.Status = .finding
    @State private var choosingLocation = false
    @State private var showLocationGuidance = false
    @State private var showBackupPicker = false
    @State private var chooseBackupManually = false
    @State private var backupCandidates: [URL] = []
    @State private var searchingBackups = false
    @State private var backupSearchFinished = false
    @State private var showEncryptionGuidance = false
    @State private var source: Archives.BackupSource?
    @State private var choseNewLocation = false
    @State private var batteryInformation: [DeviceInfoField] = []
    @State private var storageInformation: [DeviceInfoField] = []
    @State private var applications: [InstalledApplication] = []
    @State private var iconReadProgress: Progress?
    @State private var isReadingApplications = false
    @State private var didReadApplications = false
    @State private var applicationReadFailed = false
    @State private var didReadInformation = false
    private enum Pane: String, CaseIterable, Identifiable {
        case general, applications, information
        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .general: "General"
            case .applications: "Installed Apps"
            case .information: "Device Information"
            }
        }
    }
    @State private var pane: Pane = .general
    @State private var search = ""
    @State private var informationCategory = 0
    @State private var selectedInformation: String?

    private var deviceInformation: [DeviceInfoField] {
        DeviceInfoField.rows(from: vm.selectedDeviceRecord?.dictionary)
    }

    private var backupBusy: Bool {
        encryptionInProgress || choosingLocation || checkingRestoreBackup || renamingDevice
    }


    var body: some View {
        VStack(spacing: 0) {
            deviceHeader
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
            Divider()
            Picker("View", selection: $pane) {
                ForEach(Pane.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.vertical, 10)
            Divider()
            if pane == .general {
                generalView
            } else {
                informationTable
            }
            Divider()
            bottomBar
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(isPresented: $showingRename) { renameSheet }
        .sheet(isPresented: $showingBackupContents) {
            BackupContentsView(initialURL: latestBackup?.url)
        }
        .confirmationDialog("先选择备份位置", isPresented: $showLocationGuidance, titleVisibility: .visible) {
            Button("选择备份文件夹…", action: chooseNewLocation)
            Button("更新备份…", action: openBackupPicker)
            Button("取消", role: .cancel) {}
        } message: {
            Text("选择保存位置后，再点击“开始备份”。")
        }
        .sheet(isPresented: $showBackupPicker, onDismiss: {
            if chooseBackupManually {
                chooseBackupManually = false
                chooseExistingBackup()
            }
        }) { existingBackupPicker }
        .alert("暂时无法开始备份", isPresented: $showEncryptionGuidance) {
            Button("重新检查") {
                encryptionStatus = .finding
                didReadInformation = false
                readAdditionalInformation()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(encryptionStatus == .finding ? "正在检查设备加密状态，请稍候。" : "未能读取设备的加密状态。请解锁 iPhone 后重新检查。")
        }
        .onAppear {
            readAdditionalInformation()
            loadLatestBackup()
        }
        .onDisappear {
            iconReadProgress?.cancel()
            onBusyChange(false)
        }
        .onChange(of: encryptionInProgress || choosingLocation || checkingRestoreBackup || renamingDevice) {
            onBusyChange(encryptionInProgress || choosingLocation || checkingRestoreBackup || renamingDevice)
        }
        .onReceive(batteryTimer) { _ in
            if scenePhase == .active { refreshBattery() }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { refreshBattery() }
        }
        .onChange(of: pane) {
            search = ""
            if pane == .applications { readApplications() }
        }
    }

    private var deviceHeader: some View {
        HStack(spacing: 16) {
            Image(systemName: vm.selectedDeviceIcon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(vm.selectedDeviceName ?? String(localized: "Unnamed Device"))
                        .font(.title2.bold())
                    Button {
                        deviceNameDraft = vm.selectedDeviceName ?? ""
                        renameError = nil
                        showingRename = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("修改设备名称")
                    .accessibilityLabel("修改设备名称")
                    .disabled(backupBusy)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        deviceModel
                        capacityLabel
                        batteryLabel
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        deviceModel
                        HStack(spacing: 12) {
                            capacityLabel
                            batteryLabel
                        }
                    }
                }
                .foregroundStyle(.secondary)
                .font(.callout)
            }
            Spacer(minLength: 0)
        }
    }

    private var renameSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("修改设备名称").font(.title2.weight(.semibold))
            Text("新名称会同步到这台 iPhone。")
                .foregroundStyle(.secondary)
            TextField("设备名称", text: $deviceNameDraft)
                .textFieldStyle(.roundedBorder)
                .disabled(renamingDevice)
                .onSubmit { saveDeviceName() }
            if let renameError {
                Text(renameError).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if renamingDevice { ProgressView().controlSize(.small) }
                Spacer()
                Button("取消", role: .cancel) { showingRename = false }
                    .keyboardShortcut(.cancelAction)
                    .disabled(renamingDevice)
                Button("保存", action: saveDeviceName)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(renamingDevice || deviceNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
        .interactiveDismissDisabled(renamingDevice)
    }

    private func saveDeviceName() {
        let name = deviceNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !renamingDevice, !name.isEmpty, let identifier = vm.deviceIdentifier else { return }
        renamingDevice = true
        renameError = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try AppleMobileDeviceManager.shared.renameDevice(udid: identifier, name: name) }
            DispatchQueue.main.async {
                renamingDevice = false
                guard vm.deviceIdentifier == identifier else { return }
                switch result {
                case .success:
                    vm.selectedDeviceName = name
                    showingRename = false
                case let .failure(error):
                    renameError = error.localizedDescription
                }
            }
        }
    }

    private var deviceModel: some View {
        Text(vm.selectedDeviceModel ?? String(localized: "Unknown Model"))
    }

    @ViewBuilder private var capacityLabel: some View {
        if let capacity = totalCapacity {
            Text(ByteCountFormatter.string(fromByteCount: capacity, countStyle: .file))
                .monospacedDigit()
        }
    }

    @ViewBuilder private var batteryLabel: some View {
        let status = DeviceBatteryStatus(values: Dictionary(uniqueKeysWithValues: batteryInformation.map { ($0.key, $0.value) }))
        if let percentage = status.percentage {
            HStack(spacing: 6) {
                Image(systemName: status.symbol)
                    .foregroundStyle(status.isCharging == true ? Color.green : percentage <= 20 ? Color.red : Color.secondary)
                    .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 0.5)
                    .accessibilityHidden(true)
                Text("\(percentage)%").monospacedDigit()
            }
            .help(status.isCharging == true ? String(localized: "Charging") : status.isCharging == false ? String(localized: "Not Charging") : String(localized: "Unknown"))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Battery Level"))
            .accessibilityValue("\(percentage)%, \(status.isCharging == true ? String(localized: "Charging") : status.isCharging == false ? String(localized: "Not Charging") : String(localized: "Unknown"))")
        }
    }

    private var generalView: some View {
        GeometryReader { detail in
            ScrollView {
                VStack(spacing: 0) {
                    settingsRow("Software", compact: detail.size.width < 620) {
                        VStack(alignment: .leading, spacing: 10) {
                            if let version = vm.selectedDeviceVersion {
                                Text("iOS \(version)").fontWeight(.medium)
                            }
                            if let serial = vm.selectedDeviceRecord?.serialNumber {
                                HStack(spacing: 8) {
                                    Text("Serial Number").foregroundStyle(.secondary)
                                    Text(serial).monospaced().textSelection(.enabled)
                                }
                                .font(.callout)
                            }
                            Button {
                                pane = .information
                            } label: {
                                Text("Device Information")
                            }
                        }
                    }
                    Divider()
                    settingsRow("Backup", compact: detail.size.width < 620) {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("Back up all device data to this Mac", systemImage: "desktopcomputer")
                                .fontWeight(.medium)
                            backupLocationSelection
                            BackupEncryptionIndicatorView(isEnabling: $encryptionInProgress, status: $encryptionStatus)
                            BackupApplicationView()
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .center, spacing: 20) {
                                    latestBackupDescription
                                    Spacer(minLength: 16)
                                    restoreBackupButton
                                }
                                VStack(alignment: .leading, spacing: 12) {
                                    latestBackupDescription
                                    restoreBackupButton
                                }
                            }
                        }
                    }
                    Divider()
                    settingsRow("Storage", compact: detail.size.width < 620) {
                        VStack(alignment: .leading, spacing: 12) {
                            if let available = availableCapacity {
                                LabeledContent("Available Storage") {
                                    Text(ByteCountFormatter.string(fromByteCount: available, countStyle: .file))
                                        .monospacedDigit()
                                }
                            } else {
                                Text("Storage information is unavailable.")
                                    .foregroundStyle(.secondary)
                            }
                            Button {
                                informationCategory = 2
                                pane = .information
                            } label: {
                                Text("Storage Information…")
                            }
                        }
                    }
                }
                .padding(.horizontal, detail.size.width < 620 ? 24 : 40)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func settingsRow<Content: View>(_ title: LocalizedStringKey, compact: Bool, @ViewBuilder content: () -> Content) -> some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title).fontWeight(.semibold)
                    content()
                }
            } else {
                HStack(alignment: .top, spacing: 20) {
                    Text(title)
                        .fontWeight(.semibold)
                        .frame(width: 100, alignment: .trailing)
                    content()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }

    private var latestBackupDescription: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Latest Completed Backup")
                .font(.callout)
                .foregroundStyle(.secondary)
            if loadingBackupHistory {
                Text("Finding backups…").foregroundStyle(.secondary)
            } else if let latestBackup {
                Text(latestBackup.date.formatted(date: .abbreviated, time: .shortened))
                Text([latestBackup.displayName, latestBackup.systemVersion.isEmpty ? "" : "iOS \(latestBackup.systemVersion)"].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("No Completed Backups")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var restoreBackupButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if checkingRestoreBackup { ProgressView().controlSize(.small) }
                Button("Restore Backup…", action: openRestore)
            }
            Button("打开备份…") { showingBackupContents = true }
        }
        .disabled(backupBusy)
        .fixedSize()
    }

    private func loadLatestBackup() {
        guard let identifier = vm.deviceIdentifier else { return }
        loadingBackupHistory = true
        DispatchQueue.global(qos: .utility).async {
            let latest = Archives.availableBackups(for: identifier).first
            DispatchQueue.main.async {
                guard vm.deviceIdentifier == identifier else { return }
                latestBackup = latest
                loadingBackupHistory = false
            }
        }
    }

    private func openRestore() {
        guard let identifier = vm.deviceIdentifier else { return }
        guard let latestBackup else {
            vm.mode = .restore
            vm.page = .prepareRestore
            return
        }
        checkingRestoreBackup = true
        DispatchQueue.global(qos: .userInitiated).async {
            let info = Archives.validateRestoreArchive(at: latestBackup.url)
            DispatchQueue.main.async {
                checkingRestoreBackup = false
                guard vm.deviceIdentifier == identifier else { return }
                guard info.verified else {
                    loadLatestBackup()
                    Archives.presentArchiveBroken(info: info)
                    return
                }
                vm.restoreLocation = latestBackup.url.path
                vm.restoreArchiveIsPasswordProtected = info.isEncrypted
                vm.restoreApplicationsCount = info.applications
                vm.restoreArchiveSystemBuildVersion = info.systemBuildVersion
                vm.mode = .restore
                vm.page = .prepareRestore
            }
        }
    }

    private var backupLocationSelection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("备份目录").font(.callout).foregroundStyle(.secondary)
                Button("修改…", action: chooseNewLocation).disabled(backupBusy)
            }
            if let source {
                Text(source.url.deletingLastPathComponent().path).textSelection(.enabled).lineLimit(3)
                Group {
                    switch source.mode {
                    case .incremental:
                        Text("A new incremental version will be created. The selected backup stays unchanged.")
                    case .resumeIncremental:
                        Text("The unfinished incremental version will continue from its previous complete snapshot.")
                    case .retryFull:
                        Text("This backup has no verified incremental checkpoint. Retrying may transfer all device data again.")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            } else if choseNewLocation {
                Text(URL(fileURLWithPath: vm.backupLocation).deletingLastPathComponent().path).textSelection(.enabled).lineLimit(3)
                Text("此文件夹没有这台设备的已完成备份，将新建备份。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Choose a backup location before starting.").foregroundStyle(.secondary)
            }
            HStack {
                if source != nil || choseNewLocation {
                    Button("Show In Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([source?.url ?? URL(fileURLWithPath: vm.backupLocation).deletingLastPathComponent()])
                    }
                }
            }
        }
    }

    private var tableFields: [DeviceInformationPresentation.Row] {
        let fields: [DeviceInfoField]
        switch informationCategory {
        case 1: fields = batteryInformation
        case 2: fields = storageInformation
        default: fields = deviceInformation
        }
        let readable = DeviceInformationPresentation.rows(values: Dictionary(uniqueKeysWithValues: fields.map { ($0.key, $0.value) }))
        guard !search.isEmpty else { return readable }
        return readable.filter {
            $0.title.localizedCaseInsensitiveContains(search)
                || $0.value.localizedCaseInsensitiveContains(search)
                || $0.detail.localizedCaseInsensitiveContains(search)
        }
    }

    private var informationTable: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    tableControls
                }
                VStack(alignment: .leading, spacing: 8) {
                    tableControls
                }
            }
            .padding(16)
            if pane == .applications && isReadingApplications {
                ProgressView("Reading installed apps…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if pane == .applications && applicationReadFailed {
                ContentUnavailableView {
                    Label("Could not read installed apps.", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("Retry", action: readApplications)
                }
            } else if pane == .applications {
                applicationTable
            } else {
                Table(tableFields, selection: $selectedInformation) {
                    TableColumn("Information Item") { field in
                        Text(field.title).lineLimit(2).padding(.vertical, 6)
                    }
                    .width(min: 145, ideal: 210)
                    TableColumn("Current Value") { field in
                        Text(field.value).lineLimit(2).textSelection(.enabled)
                            .help(field.value)
                    }
                    .width(min: 100, ideal: 170)
                    TableColumn("Meaning") { field in
                        Text(field.detail).font(.callout).foregroundStyle(.secondary)
                            .lineLimit(2).help(field.detail)
                    }
                    .width(min: 160, ideal: 380)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: false))
                .overlay {
                    if tableFields.isEmpty {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
        }
    }

    private var filteredApplications: [InstalledApplication] {
        guard !search.isEmpty else { return applications }
        return applications.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.id.localizedCaseInsensitiveContains(search)
                || $0.version.localizedCaseInsensitiveContains(search)
        }
    }

    private var applicationTable: some View {
        Table(filteredApplications, selection: $selectedInformation) {
            TableColumn("Application") { app in
                HStack(spacing: 10) {
                    Group {
                        if let icon = app.icon {
                            Image(nsImage: icon).resizable().scaledToFit()
                        } else {
                            Image(systemName: "app.dashed")
                                .resizable().scaledToFit()
                                .foregroundStyle(.secondary)
                                .padding(3)
                        }
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(.rect(cornerRadius: 6))
                    .accessibilityHidden(true)
                    Text(app.name).lineLimit(1)
                }
                .padding(.vertical, 4)
            }
            .width(min: 170, ideal: 280)
            TableColumn("Version", value: \.version)
                .width(min: 70, ideal: 100, max: 160)
            TableColumn("Bundle ID") { app in
                Text(app.id).lineLimit(1).foregroundStyle(.secondary).textSelection(.enabled)
            }
            .width(min: 130, ideal: 280)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .overlay {
            if filteredApplications.isEmpty { ContentUnavailableView.search(text: search) }
        }
    }

    @ViewBuilder private var tableControls: some View {
        if pane == .information {
            Picker("Category", selection: $informationCategory) {
                Text("Device").tag(0)
                Text("Battery").tag(1)
                Text("Storage").tag(2)
            }
            .labelsHidden()
            .fixedSize()
        } else {
            Text("Installed Apps").font(.headline)
        }
        Spacer(minLength: 0)
        TextField("Filter", text: $search)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 140, maxWidth: 260)
    }

    private var totalCapacity: Int64? {
        storageInformation.first(where: { $0.key == "TotalDiskCapacity" })
            .flatMap { Int64($0.value) }
    }

    private var availableCapacity: Int64? {
        storageInformation.first(where: { $0.key == "AmountDataAvailable" })
            .flatMap { Int64($0.value) }
    }

    private var backupActions: some View {
        startButton
    }

    private var bottomBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
                storageBar
                Spacer(minLength: 0)
                backupActions
            }
            VStack(alignment: .leading, spacing: 12) {
                storageBar
                HStack { Spacer(); backupActions }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.bar)
    }

    private var storageBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let total = totalCapacity, let available = availableCapacity, total > 0 {
                let summary = "已用空间：\(ByteCountFormatter.string(fromByteCount: max(0, total - available), countStyle: .file))\n剩余空间：\(ByteCountFormatter.string(fromByteCount: available, countStyle: .file))\n总容量：\(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
                GeometryReader { geometry in
                    let used = min(1, max(0, Double(total - available) / Double(total)))
                    HStack(spacing: 0) {
                        Rectangle().fill(Color(nsColor: .controlAccentColor)).frame(width: geometry.size.width * used)
                        Rectangle().fill(.primary.opacity(0.08))
                    }
                    .clipShape(.rect(cornerRadius: 4))
                }
                .frame(height: 10)
                .contentShape(.rect)
                .help(summary)
                .accessibilityLabel("设备存储空间")
                .accessibilityValue(summary)
                HStack {
                    Text("已使用：\(ByteCountFormatter.string(fromByteCount: max(0, total - available), countStyle: .file))")
                    Spacer()
                    Text("剩余：\(ByteCountFormatter.string(fromByteCount: available, countStyle: .file))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(summary)
            } else {
                Label("USB", systemImage: "cable.connector")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 180, maxWidth: .infinity)
    }

    private var startButton: some View {
        HStack(spacing: 8) {
            if choosingLocation { ProgressView().controlSize(.small) }
            Button(action: startBackup) {
                Group {
                    if choosingLocation {
                        Text("Preparing Backup…")
                    } else {
                        Text("Start Backup")
                    }
                }
                .padding(.horizontal, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(backupBusy)
            .help(source == nil && !choseNewLocation ? "点击选择备份位置" : "Start Backup")
        }
        .fixedSize()
    }

    private func readAdditionalInformation() {
        guard !didReadInformation, let udid = vm.deviceIdentifier else { return }
        didReadInformation = true
        isReadingBattery = true
        DispatchQueue.global(qos: .utility).async {
            let manager = AppleMobileDeviceManager.shared
            let values = manager.readLockdownValues(udid: udid, domains: [
                "com.apple.mobile.battery", "com.apple.disk_usage", "com.apple.mobile.backup",
            ], connection: .usb)
            let battery = DeviceInfoField.rows(from: values["com.apple.mobile.battery"]?.value)
            let storage = DeviceInfoField.rows(from: values["com.apple.disk_usage"]?.value)
            let backup = values["com.apple.mobile.backup"]?.value as? [String: Any]
            let encrypted = (backup?["WillEncrypt"] as? Bool)
                ?? BackupEncryptionIndicatorView.readDeviceStatus(udid: udid)
            DispatchQueue.main.async {
                guard vm.deviceIdentifier == udid else { return }
                isReadingBattery = false
                batteryInformation = battery
                storageInformation = storage
                encryptionStatus = encrypted.map { $0 ? .enabled : .disabled } ?? .unknown
                vm.backupEncrypted = encrypted ?? false
            }
        }
    }

    private func refreshBattery() {
        guard didReadInformation, !isReadingBattery, !encryptionInProgress,
              let udid = vm.deviceIdentifier else { return }
        isReadingBattery = true
        DispatchQueue.global(qos: .utility).async {
            let battery = DeviceInfoField.rows(from: AppleMobileDeviceManager.shared.readFromLockdown(
                udid: udid, domain: "com.apple.mobile.battery", connection: .usb
            )?.value)
            DispatchQueue.main.async {
                isReadingBattery = false
                guard vm.deviceIdentifier == udid else { return }
                // A failed request must not present an old percentage as a fresh reading.
                batteryInformation = battery
            }
        }
    }

    private func readApplications() {
        guard !didReadApplications, !isReadingApplications, let udid = vm.deviceIdentifier else { return }
        isReadingApplications = true
        applicationReadFailed = false
        let progress = Progress(totalUnitCount: 0)
        iconReadProgress?.cancel()
        iconReadProgress = progress
        DispatchQueue.global(qos: .utility).async {
            let manager = AppleMobileDeviceManager.shared
            let apps = manager.listApplications(udid: udid, connection: .usb, includeIcons: false)
            let records = apps?.map { identifier, data -> InstalledApplication in
                let values = data.value as? [String: AnyCodable]
                let name = values?["CFBundleDisplayName"]?.value as? String ?? identifier
                let version = values?["CFBundleShortVersionString"]?.value as? String ?? "—"
                return InstalledApplication(id: identifier, name: name, version: version)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } ?? []
            progress.totalUnitCount = Int64(records.count)
            DispatchQueue.main.async {
                guard vm.deviceIdentifier == udid, !progress.isCancelled else { progress.cancel(); return }
                applications = records
                isReadingApplications = false
                didReadApplications = apps != nil
                applicationReadFailed = apps == nil
            }
            guard apps != nil else { return }
            manager.readApplicationIcons(udid: udid, identifiers: records.map(\.id), progress: progress) { identifier, data in
                guard !progress.isCancelled,
                      let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
                          kCGImageSourceThumbnailMaxPixelSize: 64,
                          kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceCreateThumbnailWithTransform: true,
                          kCGImageSourceShouldCacheImmediately: true,
                      ] as CFDictionary) else { return }
                let image = NSImage(cgImage: thumbnail, size: NSSize(width: 28, height: 28))
                DispatchQueue.main.async {
                    guard vm.deviceIdentifier == udid, !progress.isCancelled else { return }
                    applications.first(where: { $0.id == identifier })?.icon = image
                }
            }
        }
    }

    private var readableDeviceName: String {
        let name = vm.selectedDeviceName ?? ""
        let model = vm.selectedDeviceModel ?? "iPhone"
        return name.isEmpty || name == model ? model : "\(name) · \(model)"
    }

    private func chooseNewLocation() {
        guard let window = NSApp.mainWindow ?? NSApp.windows.first,
              let identifier = vm.deviceIdentifier else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择备份文件夹。有这台设备的历史备份时自动增量更新，否则新建备份。"
        panel.prompt = "选择"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let folder = panel.url else { return }
            choosingLocation = true
            let deviceName = readableDeviceName
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result { try Archives.latestBackupSource(in: folder, deviceIdentifier: identifier) }
                DispatchQueue.main.async {
                    choosingLocation = false
                    guard vm.deviceIdentifier == identifier else { return }
                    switch result {
                    case let .success(existing):
                        source = existing
                        choseNewLocation = existing == nil
                        if existing == nil {
                            vm.backupLocation = Archives.newBackupURL(in: folder, deviceName: deviceName).path
                        }
                    case let .failure(error):
                        NSAlert(error: error).beginSheetModal(for: window)
                    }
                }
            }
        }
    }

    private func chooseExistingBackup() {
        guard let window = NSApp.mainWindow ?? NSApp.windows.first,
              let archiveType = UTType("tech.nootag.itm.backup")
        else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [archiveType]
        panel.message = NSLocalizedString("Choose an Existing Backup", comment: "")
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            selectBackup(url)
        }
    }

    private func selectBackup(_ url: URL) {
        guard let identifier = vm.deviceIdentifier else { return }
        choosingLocation = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Archives.inspectBackupSource(at: url, deviceIdentifier: identifier) }
            DispatchQueue.main.async {
                choosingLocation = false
                guard vm.deviceIdentifier == identifier else { return }
                switch result {
                case let .success(value):
                    Archives.trackBackup(at: url)
                    source = value
                    choseNewLocation = false
                    showBackupPicker = false
                case let .failure(error):
                    NSAlert(error: error).runModal()
                }
            }
        }
    }

    private func openBackupPicker() {
        backupCandidates = []
        backupSearchFinished = false
        showBackupPicker = true
        findBackups(searchComputer: false)
    }

    private func findBackups(searchComputer: Bool) {
        guard let identifier = vm.deviceIdentifier else { return }
        searchingBackups = true
        DispatchQueue.global(qos: .utility).async {
            let urls = Archives.backupCandidates(for: identifier, searchComputer: searchComputer)
            DispatchQueue.main.async {
                guard vm.deviceIdentifier == identifier else { return }
                backupCandidates = urls
                searchingBackups = false
                backupSearchFinished = searchComputer
            }
        }
    }

    private var existingBackupPicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("更新备份").font(.title2).fontWeight(.semibold)
            Text("选择这台设备的已有备份。更新时会保留已完成的原备份。")
                .foregroundStyle(.secondary)
            HStack {
                Text(backupSearchFinished ? "本机搜索结果" : "历史记录")
                Spacer()
                if searchingBackups { ProgressView().controlSize(.small) }
                Button("搜索电脑", systemImage: "magnifyingglass") { findBackups(searchComputer: true) }
                    .disabled(searchingBackups || choosingLocation)
            }
            List(backupCandidates, id: \.path) { url in
                Button { selectBackup(url) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "externaldrive").font(.title2).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Text(url.deletingLastPathComponent().path)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(choosingLocation || searchingBackups)
            }
            .overlay {
                if backupCandidates.isEmpty && !searchingBackups {
                    ContentUnavailableView {
                        Label(backupSearchFinished ? "未找到匹配的备份" : "暂无备份记录", systemImage: "archivebox")
                    } description: {
                        Text(backupSearchFinished ? "搜索仅包含 Spotlight 已索引的位置，也可以手动选择备份。" : "可以搜索电脑，或手动选择备份文件。")
                    }
                }
            }
            HStack {
                Button("手动选择…") {
                    chooseBackupManually = true
                    showBackupPicker = false
                }
                .disabled(choosingLocation || searchingBackups)
                Spacer()
                Button("取消", role: .cancel) { showBackupPicker = false }
                    .keyboardShortcut(.cancelAction)
                    .disabled(choosingLocation)
            }
        }
        .padding(24)
        .frame(width: 590, height: 430)
        .interactiveDismissDisabled(choosingLocation)
    }

    private func startBackup() {
        guard !backupBusy else { return }
        pane = .general
        guard source != nil || choseNewLocation else {
            chooseNewLocation()
            return
        }
        guard encryptionStatus == .enabled || encryptionStatus == .disabled else {
            showEncryptionGuidance = true
            return
        }
        guard let source else {
            guard choseNewLocation else { return }
            do {
                try FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: vm.backupLocation), withIntermediateDirectories: false
                )
                vm.page = .backupProgress
            } catch {
                NSAlert(error: error).runModal()
            }
            return
        }

        choosingLocation = true
        let deviceName = readableDeviceName
        let identifier = vm.deviceIdentifier ?? ""
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () throws -> URL in
                let current = try Archives.inspectBackupSource(
                    at: source.url,
                    deviceIdentifier: identifier
                )
                switch (source.mode, current.mode) {
                case (.incremental, .incremental):
                    return try Archives.makeIncrementalVersion(from: source.url, deviceName: deviceName)
                case (.resumeIncremental, .resumeIncremental), (.retryFull, .retryFull):
                    return source.url
                default:
                    throw Archives.BackupSourceError.invalid
                }
            }
            DispatchQueue.main.async {
                choosingLocation = false
                switch result {
                case let .success(url):
                    vm.backupLocation = url.path
                    vm.page = .backupProgress
                case let .failure(error):
                    if let window = NSApp.mainWindow ?? NSApp.windows.first {
                        NSAlert(error: error).beginSheetModal(for: window)
                    }
                }
            }
        }
    }
}

private struct DeviceInfoField: Identifiable {
    let key: String
    let value: String

    var id: String { key }

    static func rows(from raw: Any?) -> [DeviceInfoField] {
        if let wrapped = raw as? AnyCodable { return rows(from: wrapped.value) }
        guard let dictionary = raw as? [String: Any] else { return [] }
        return dictionary.keys.sorted().compactMap { key in
            guard let value = dictionary[key] else { return nil }
            return DeviceInfoField(key: key, value: format(value))
        }
    }

    private static func format(_ value: Any) -> String {
        if let wrapped = value as? AnyCodable { return format(wrapped.value) }
        if let data = value as? Data {
            return "Binary data (\(data.count) bytes)"
        }
        if let date = value as? Date {
            return date.formatted(date: .numeric, time: .standard)
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.keys.sorted().compactMap { key in
                dictionary[key].map { "\(key): \(format($0))" }
            }.joined(separator: "\n")
        }
        if let array = value as? [Any] {
            return array.map { format($0) }.joined(separator: ", ")
        }
        return String(describing: value)
    }
}

@Observable
private final class InstalledApplication: Identifiable {
    let id: String
    let name: String
    let version: String
    var icon: NSImage?

    init(id: String, name: String, version: String) {
        self.id = id
        self.name = name
        self.version = version
    }
}

private struct BackupContentsView: View {
    let initialURL: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var contents: BackupContents?
    @State private var loading = false
    @State private var error: String?
    @State private var query = ""
    @State private var requestID = UUID()
    @State private var tab = 0

    private var filteredApps: [BackupContents.App] {
        guard let apps = contents?.apps else { return [] }
        return query.isEmpty ? apps : apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("备份内容").font(.title2.weight(.semibold))
                Spacer()
                if loading { ProgressView().controlSize(.small) }
            }
            if let contents {
                Picker("内容", selection: $tab) {
                    Text("概览").tag(0)
                    Text("应用（\(contents.apps.count)）").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if tab == 0 {
                    HStack(alignment: .top, spacing: 32) {
                        overviewFields(Array(contents.fields.prefix(7)))
                        overviewFields(Array(contents.fields.dropFirst(7)))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                HStack {
                    Text("应用（\(contents.apps.count)）").font(.headline)
                    Spacer()
                    TextField("搜索应用", text: $query).textFieldStyle(.roundedBorder).frame(width: 240)
                }
                Text(contents.sizeExplanation)
                    .font(.caption).foregroundStyle(.secondary)
                Table(filteredApps) {
                    TableColumn("应用") { app in
                        HStack(spacing: 8) {
                            if let data = app.icon, let image = NSImage(data: data) {
                                Image(nsImage: image).resizable().scaledToFit().frame(width: 24, height: 24)
                            } else {
                                Image(systemName: "app").frame(width: 24, height: 24).foregroundStyle(.secondary)
                            }
                            Text(app.name).lineLimit(1)
                        }
                    }
                    TableColumn("版本", value: \.version).width(min: 60, ideal: 90, max: 120)
                    TableColumn("应用本体", value: \.appSize).width(min: 100, ideal: 120, max: 150)
                    TableColumn("备份数据", value: \.dataSize).width(min: 100, ideal: 120, max: 150)
                }
                .overlay {
                    if filteredApps.isEmpty {
                        ContentUnavailableView(query.isEmpty ? "备份未提供应用清单" : "没有匹配的应用", systemImage: "app.dashed")
                    }
                }
                }
                Text(contents.url.path).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).textSelection(.enabled)
            } else if !loading {
                ContentUnavailableView("选择备份以查看内容", systemImage: "archivebox")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("打开其他备份…", action: chooseArchive).disabled(loading)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 850, height: 600)
        .onAppear {
            if let initialURL { load(initialURL) }
        }
        .onDisappear { requestID = UUID() }
    }

    private func overviewFields(_ fields: [BackupContents.Field]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 16) {
            ForEach(fields) { field in
                GridRow(alignment: .top) {
                    Text(field.title).foregroundStyle(.secondary).fixedSize()
                    Text(field.value).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func chooseArchive() {
        guard let window = NSApp.keyWindow else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType("tech.nootag.itm.backup") ?? .directory]
        panel.message = "选择要查看的备份"
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url { load(url) }
        }
    }

    private func load(_ url: URL) {
        let identifier = UUID()
        requestID = identifier
        loading = true
        error = nil
        query = ""
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try BackupContents.read(url) }
            DispatchQueue.main.async {
                guard requestID == identifier else { return }
                loading = false
                switch result {
                case let .success(value): contents = value
                case let .failure(failure): error = failure.localizedDescription
                }
            }
        }
    }
}

private struct BackupContents {
    struct Field: Identifiable {
        let title: String
        let value: String
        var id: String { title }
    }
    struct App: Identifiable {
        let id: String
        let name: String
        let version: String
        let icon: Data?
        let appSize: String
        let dataSize: String
    }
    let url: URL
    let fields: [Field]
    let apps: [App]
    let sizeExplanation: String

    static func read(_ url: URL) throws -> Self {
        func plist(_ name: String) -> [String: Any]? {
            guard let data = try? Data(contentsOf: url.appendingPathComponent(name)) else { return nil }
            return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        }
        guard let info = plist("Info.plist") else {
            throw NSError(domain: "iTM.BackupContents", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "无法读取备份信息，请检查备份文件和磁盘连接。"])
        }
        let status = plist("Status.plist") ?? [:]
        let manifest = plist("Manifest.plist") ?? [:]
        var fields: [Field] = []
        func add(_ title: String, _ value: Any?) {
            guard let value else { return }
            let text: String
            if let date = value as? Date { text = date.formatted(date: .abbreviated, time: .standard) }
            else if let string = value as? String { text = string }
            else if let number = value as? NSNumber { text = number.stringValue }
            else { return }
            if !text.isEmpty { fields.append(Field(title: title, value: text)) }
        }
        add("设备名称", info["Device Name"])
        let product = info["Product Type"] as? String ?? ""
        add("机型", ConnectedDevice.modelNames[product] ?? product)
        add("系统版本", info["Product Version"])
        add("系统构建版本", info["Build Version"])
        add("备份时间", status["Date"] ?? info["Last Backup Date"])
        add("序列号", info["Serial Number"])
        add("设备标识", info["Target Identifier"] ?? info["Unique Identifier"])
        if let encrypted = manifest["IsEncrypted"] as? Bool { add("加密备份", encrypted ? "是" : "否") }
        else { add("加密备份", "无法读取") }
        let state = status["SnapshotState"] as? String
        add("备份状态", state == "finished" ? "已完成" : (state == "uploading" ? "未完成" : "无法确认"))
        let pending = FileManager.default.fileExists(atPath: url.appendingPathComponent(Archives.pendingMarkerName).path)
        if pending { add("归档状态", "尚未完成校验，不能确认可用于恢复") }
        if let full = status["IsFullBackup"] as? Bool { add("备份方式", full ? "完整备份" : "增量备份") }
        for (key, title) in [("IMEI", "IMEI"), ("MEID", "MEID"), ("ICCID", "SIM 卡标识"), ("Phone Number", "电话号码"), ("iTunes Version", "备份协议版本")] {
            add(title, info[key])
        }
        let applications = info["Applications"] as? [String: [String: Any]] ?? [:]
        let identifiers = Set(applications.keys).union(info["Installed Applications"] as? [String] ?? [])
        let encrypted = manifest["IsEncrypted"] as? Bool ?? true
        let sizes = encrypted ? nil : readDataSizes(url)
        let snapshot = plist(".itm-app-usage.plist")
        let identifier = (info["Target Identifier"] as? String) ?? (info["Unique Identifier"] as? String)
        let snapshotMatches = identifier != nil && snapshot?["DeviceIdentifier"] as? String == identifier
        let deviceSizes = snapshotMatches ? (snapshot?["Applications"] as? [String: [String: NSNumber]] ?? [:]) : [:]
        if snapshotMatches { add("应用占用采集时间", snapshot?["CapturedAt"]) }
        let apps = identifiers.map { id in
            let app = applications[id] ?? [:]
            let metadata: [String: Any]
            if let data = app["iTunesMetadata"] as? Data {
                metadata = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] ?? [:]
            } else { metadata = [:] }
            let name = (metadata["itemName"] as? String) ?? (metadata["bundleDisplayName"] as? String) ?? id
            let version = (metadata["bundleShortVersionString"] as? String) ?? (metadata["bundleVersion"] as? String) ?? "未提供"
            let recordedAppSize = deviceSizes[id]?["StaticDiskUsage"] ?? (app["StaticDiskUsage"] as? NSNumber)
            let appSize = recordedAppSize.map { ByteCountFormatter.string(fromByteCount: $0.int64Value, countStyle: .file) } ?? "未记录"
            let dataSize: String
            if let recordedData = deviceSizes[id]?["DynamicDiskUsage"] {
                dataSize = ByteCountFormatter.string(fromByteCount: recordedData.int64Value, countStyle: .file)
            } else if encrypted { dataSize = "索引已加密" }
            else if let bytes = sizes?[id] { dataSize = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
            else { dataSize = sizes == nil ? "无法读取" : "未找到数据" }
            return App(id: id, name: name, version: version, icon: app["PlaceholderIcon"] as? Data,
                       appSize: appSize, dataSize: dataSize)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return Self(url: url, fields: fields, apps: apps,
                    sizeExplanation: !deviceSizes.isEmpty
                        ? "已记录的占用为备份开始时手机上的应用本体与数据大小，不等同于归档文件大小；缺失项不作估算。"
                        : encrypted
                        ? "此备份的文件索引已加密，暂无法统计应用数据；未记录的应用本体大小不作估算。"
                        : "数据大小按备份中的应用独立容器统计，不含共享容器；应用本体大小仅在备份有记录时显示。")
    }

    private static func readDataSizes(_ url: URL) -> [String: Int64]? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.appendingPathComponent("Manifest.db").path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            return nil
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT domain, file FROM Files WHERE flags = 1 AND domain LIKE 'AppDomain-%'", -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        var result: [String: Int64] = [:]
        var state = sqlite3_step(statement)
        while state == SQLITE_ROW {
            guard let domainPointer = sqlite3_column_text(statement, 0),
                  let bytes = sqlite3_column_blob(statement, 1) else { return nil }
            let domain = String(cString: domainPointer)
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 1)))
            guard let archive = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                  let objects = archive["$objects"] as? [Any],
                  let size = objects.compactMap({ ($0 as? [String: Any])?["Size"] as? NSNumber }).first else { return nil }
            let identifier = String(domain.dropFirst("AppDomain-".count))
            let previous = result[identifier, default: 0]
            guard size.int64Value >= 0, size.int64Value <= Int64.max - previous else { return nil }
            result[identifier] = previous + size.int64Value
            state = sqlite3_step(statement)
        }
        return state == SQLITE_DONE ? result : nil
    }
}
