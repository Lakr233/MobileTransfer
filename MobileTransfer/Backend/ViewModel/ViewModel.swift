//
//  ViewModel.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import Cocoa
import ColorfulX
import DockProgress
import Observation
import UniformTypeIdentifiers

@Observable
class ViewModel {
    static let shared = ViewModel()

    static let defaultBackupLocation = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("iTM")

    enum Page: String {
        case welcome
        case actionMenu
        case findDevice
        case prepareBackup
        case backupProgress
        case prepareRestore
        case restoreProgress
        case installApplication
    }

    var navigationArray: [Page] = [.welcome]

    enum Mode {
        case unspecified
        case backup
        case restore
    }

    var mode: Mode = .unspecified

    var deviceIdentifier: String?
    var selectedDeviceName: String?
    var selectedDeviceModel: String?
    var selectedDeviceVersion: String?
    var selectedDeviceIcon = "iphone"
    var selectedDeviceRecord: AppleMobileDeviceManager.DeviceRecord?

    // MARK: - backup

    /// sandbox will block our access to these path after reopen
    var backupLocation: String = defaultBackupLocation
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("mobiletransfer")
        .path

    var backupApps: Bool = false

    // passed from view
    var backupEncrypted: Bool = false
    var backupApplicationList: [App] = []
    var backupApplicationAccountAllowed: Set<String> = []

    var backupTask: BackupTask?



    // MARK: - restore

    enum RestoreMode: String, CaseIterable, Codable {
        case unspecified
        case replace // --system --settings --remove
        case merge // --system --settings --no-reboot
        case mergeWithoutInstallApplication // same as merge
    }

    var restoreLocation: String?
    var restorePassword: String = ""
    var restoreArchiveSystemBuildVersion: String = ""
    var restoreArchiveIsPasswordProtected: Bool = false
    var restoreApplicationsCount: Int = 0
    var restoreMode: RestoreMode = .unspecified

    var restoreTask: RestoreTask?
    var applicationInstallTask: MobileInstallTask?

    // MARK: - Activation

    struct LicenseInfo: Codable, Equatable {
        var licensee: String
        var licenseKey: String
        var validateTo: Date
    }

    @ObservationIgnored
    private var _licenseInfo = StoredValue(key: "LicenseInfo", defaultValue: nil as LicenseInfo?)
    var licenseInfo: LicenseInfo? {
        get {
            access(keyPath: \.licenseInfo)
            return _licenseInfo.get()
        }
        set {
            withMutation(keyPath: \.licenseInfo) {
                _licenseInfo.set(newValue)
            }
        }
    }

    var isLicenseTrail: Bool {
        guard let info = licenseInfo else { return false }
        _ = info
//        return [
//            info.licensee == Mew.trailEmail,
//            info.licenseKey == Mew.trailKey,
//        ].reduce(false) { $0 || $1 }
        return false
    }

    // MARK: - rest of us

    private init() {
        resetAll()
    }

    func resetAll() {
        backupTask?.terminate()
        restoreTask?.terminate()
        applicationInstallTask?.terminate()
        deviceIdentifier = nil
        selectedDeviceName = nil
        selectedDeviceModel = nil
        selectedDeviceVersion = nil
        selectedDeviceIcon = "iphone"
        selectedDeviceRecord = nil
        mode = .unspecified
        backupApps = false
        backupEncrypted = false
        backupApplicationList = []
        backupApplicationAccountAllowed = []
        backupTask = nil
        restoreLocation = nil
        restorePassword = ""
        restoreArchiveIsPasswordProtected = false
        restoreArchiveSystemBuildVersion = ""
        restoreApplicationsCount = 0
        restoreMode = .unspecified
        restoreTask = nil
        applicationInstallTask = nil

        DispatchQueue.main.async { DockProgress.resetProgress() }
    }
}
