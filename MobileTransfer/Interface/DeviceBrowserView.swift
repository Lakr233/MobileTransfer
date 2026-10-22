import Combine
import SwiftUI

/// The device list remains mounted while the selected device's detail changes.
struct DeviceBrowserView: View {
    @Environment(ViewModel.self) private var vm
    @State private var devices: [ConnectedDevice] = []
    @State private var selection: String?
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var scanID: UUID?
    @State private var hasScanned = false
    @State private var deviceBusy = false
    @State private var showingTrust = false
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var selectedDevice: ConnectedDevice? {
        devices.first { $0.id == selection }
    }

    var body: some View {
        GeometryReader { geometry in
            NavigationSplitView(columnVisibility: $columns) {
                List(selection: $selection) {
                    Section("Devices") {
                        ForEach(devices) { device in
                            HStack(spacing: 10) {
                                Image(systemName: device.deviceSystemIcon)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(device.deviceName ?? String(localized: "Unnamed Device"))
                                        .lineLimit(1)
                                    Text(device.modelName ?? String(localized: "Unknown Model"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if device.deviceRecord == nil {
                                    Image(systemName: "exclamationmark.circle")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if !device.trusted {
                                    Image(systemName: "lock.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .tag(device.id)
                        }
                        if devices.isEmpty {
                            Text(hasScanned ? "No Devices" : "Scanning for devices...")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.sidebar)
                .disabled(deviceBusy)
                .navigationTitle("iTM")
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)

            } detail: {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .navigationTitle(selectedDevice?.deviceName ?? "iTM")
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            Button(action: scan) {
                                Label("Refresh Devices", systemImage: "arrow.clockwise")
                            }
                            .disabled(scanID != nil || deviceBusy)
                        }
                        if vm.page == .prepareRestore {
                            ToolbarItem(placement: .primaryAction) {
                                Button("Backup Device") {
                                    vm.mode = .backup
                                    vm.page = .prepareBackup
                                }
                                .disabled(selectedDevice?.trusted != true || deviceBusy)
                            }
                        }
                    }
            }
            .navigationSplitViewStyle(.balanced)
            .onChange(of: geometry.size.width, initial: true) { _, width in
                columns = width < 820 && selection != nil ? .detailOnly : .all
            }
            .onChange(of: selection) {
                if geometry.size.width < 820 {
                    columns = selection == nil ? .all : .detailOnly
                }
            }
        }
        .onAppear {
            if vm.page == .welcome || vm.page == .actionMenu {
                vm.resetAll()
                vm.mode = .backup
            }
            scan()
        }
        .onDisappear { scanID = nil }
        .onReceive(timer) { _ in scan() }
        .onChange(of: selection) {
            if let selectedDevice {
                activate(selectedDevice)
            } else {
                clearSelection()
            }
        }
        .onChange(of: vm.page) {
            // A dropped archive opens restore for the currently selected device.
            if vm.page == .findDevice, let selectedDevice {
                activate(selectedDevice)
            }
        }
        .sheet(isPresented: Binding(
            get: { vm.page == .prepareRestore },
            set: { presented in
                if !presented && vm.page == .prepareRestore {
                    vm.restorePassword = ""
                    vm.mode = .backup
                    vm.page = .prepareBackup
                }
            }
        )) { PrepareRestoreView() }
        .sheet(isPresented: $showingTrust, onDismiss: scan) {
            DeviceTrustView()
        }
    }

    @ViewBuilder private var detail: some View {
        if let device = selectedDevice {
            if device.deviceRecord == nil {
                ContentUnavailableView {
                    Label("Could Not Read Device", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("The USB device is connected, but its information could not be read. Unlock the device and check the cable connection.")
                } actions: {
                    Button("Refresh Devices", action: scan).disabled(scanID != nil)
                }
            } else if !device.trusted {
                ContentUnavailableView {
                    Label(device.deviceName ?? String(localized: "Device Locked"), systemImage: "lock.shield")
                } description: {
                    Text("Please trust this computer on your device.")
                } actions: {
                    Button("Trust Device…") {
                        showingTrust = true
                        let identifier = device.id
                        DispatchQueue.global(qos: .userInitiated).async {
                            AppleMobileDeviceManager.shared.sendPairRequest(udid: identifier, connection: .usb)
                        }
                    }
                }
            } else if vm.deviceIdentifier == device.id {
                PrepareBackupView { deviceBusy = $0 }
                    .id(device.id)
            } else {
                ProgressView("Reading device information…")
            }
        } else if !hasScanned {
            ProgressView("Scanning for devices...")
        } else if devices.isEmpty {
            ContentUnavailableView {
                Label("No Device Connected", systemImage: "laptopcomputer.and.iphone")
            } description: {
                Text("Please connect your device to this computer via a cable")
            } actions: {
                Button("Refresh Devices", action: scan)
                    .disabled(scanID != nil)
            }
        } else {
            ContentUnavailableView {
                Label("Select a Device", systemImage: "sidebar.left")
            } description: {
                Text("Select a device in the sidebar to view its details.")
            }
        }
    }

    private func scan() {
        guard scanID == nil, !deviceBusy else { return }
        let id = UUID()
        scanID = id
        DispatchQueue.global(qos: .utility).async {
            let manager = AppleMobileDeviceManager.shared
            let result = manager.listDeviceIdentifiers()
                .filter { manager.remoteDeviceHandlerIdentifier(udid: $0, connection: .usb) != nil }
                .map { identifier in
                ConnectedDevice(udid: identifier, deviceRecord: manager.obtainDeviceInfo(udid: identifier, connection: .usb))
            }.sorted { $0.id < $1.id }
            DispatchQueue.main.async {
                guard scanID == id else { return }
                scanID = nil
                let wasEmpty = devices.isEmpty
                let selectedDisconnected = selection.map { selected in !result.contains { $0.id == selected } } ?? false
                hasScanned = true
                devices = result
                if let selection, !result.contains(where: { $0.id == selection }) {
                    self.selection = nil
                    clearSelection()
                }
                if selection == nil, let first = result.first, wasEmpty || selectedDisconnected {
                    selection = first.id
                } else if let device = selectedDevice, device.trusted, vm.deviceIdentifier != device.id {
                    activate(device)
                }
            }
        }
    }

    private func clearSelection() {
        vm.deviceIdentifier = nil
        vm.selectedDeviceRecord = nil
        vm.selectedDeviceName = nil
        vm.selectedDeviceModel = nil
        vm.selectedDeviceVersion = nil
        vm.navigationArray = [.findDevice]
    }

    private func activate(_ device: ConnectedDevice) {
        guard device.trusted else {
            clearSelection()
            return
        }
        let changedDevice = vm.deviceIdentifier != device.id
        if changedDevice, vm.deviceIdentifier != nil {
            vm.restoreLocation = nil
            vm.restorePassword = ""
            vm.restoreMode = .unspecified
            vm.restoreArchiveIsPasswordProtected = false
        }
        vm.deviceIdentifier = device.id
        vm.selectedDeviceName = device.deviceName
        vm.selectedDeviceModel = device.modelName
        vm.selectedDeviceVersion = device.deviceRecord?.productVersion
        vm.selectedDeviceIcon = device.deviceSystemIcon
        vm.selectedDeviceRecord = device.deviceRecord
        if changedDevice {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let name = device.deviceName ?? device.id
            vm.backupLocation = ViewModel.defaultBackupLocation
                .appendingPathComponent("\(name)-\(formatter.string(from: Date())).mobiletransfer")
                .path
            vm.backupEncrypted = false
        }
        if vm.mode == .unspecified { vm.mode = .backup }
        vm.navigationArray = [vm.mode == .restore ? .prepareRestore : .prepareBackup]
    }
}
