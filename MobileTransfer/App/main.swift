//
//  main.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/24.
//

import AppleMobileDeviceLibrary
import Cocoa
import Digger
import Foundation
import SwiftUI
import ApplePackage

func print(_ items: Any..., separator: String = " ", terminator _: String = "\n") {
    let text = items.map { "\($0)" }.joined(separator: separator)
    NSLog("%@", text)
}

Security.removeDebugger()
guard Security.validateAppSignature() else {
    Security.crashOut()
}

#if DEBUG
if let index = CommandLine.arguments.firstIndex(of: "--verify-app-package"), CommandLine.arguments.count > index + 2 {
    do {
        try StorePackageValidator.validate(at: URL(fileURLWithPath: CommandLine.arguments[index + 1]), bundleID: CommandLine.arguments[index + 2])
        print("APP_PACKAGE valid=true")
        exit(0)
    } catch {
        print("APP_PACKAGE valid=false")
        exit(1)
    }
}
if let index = CommandLine.arguments.firstIndex(of: "--verify-app-usage"),
   CommandLine.arguments.count > index + 1 {
    let snapshot = AppleMobileDeviceManager.shared.applicationUsageSnapshot(udid: CommandLine.arguments[index + 1])
    let apps = snapshot?["Applications"] as? [String: [String: Int64]] ?? [:]
    let appSizes = apps.values.filter { $0["StaticDiskUsage"] != nil }.count
    let dataSizes = apps.values.filter { $0["DynamicDiskUsage"] != nil }.count
    print("APP_USAGE readable=\(snapshot != nil) apps=\(appSizes) data=\(dataSizes)")
    exit(snapshot == nil ? 1 : 0)
}
if let index = CommandLine.arguments.firstIndex(of: "--verify-device-rename"),
   CommandLine.arguments.count > index + 1 {
    let identifier = CommandLine.arguments[index + 1]
    let manager = AppleMobileDeviceManager.shared
    do {
        guard let name = manager.obtainDeviceInfo(udid: identifier, connection: .usb)?.deviceName else {
            throw NSError(domain: "iTM.RenameCheck", code: 1)
        }
        try manager.renameDevice(udid: identifier, name: name)
        try manager.renameDevice(udid: identifier, name: name)
        print("DEVICE_RENAME verified=true namePreserved=true")
        exit(0)
    } catch {
        print("DEVICE_RENAME verified=false error=\(error.localizedDescription)")
        exit(1)
    }
}
if CommandLine.arguments.contains("--verify-backup-lifecycle") {
    let valid = MobileBackupTask.verifyPreparationEvents() && BackupTask.verifyCancellation()
    print("BACKUP_LIFECYCLE verified=\(valid)")
    exit(valid ? 0 : 1)
}
if CommandLine.arguments.contains("--verify-device-presentation") {
    let valid = DeviceInformationPresentation.verify() && DeviceBatteryStatus.verify()
    print("DEVICE_PRESENTATION verified=\(valid)")
    exit(valid ? 0 : 1)
}
if CommandLine.arguments.contains("--benchmark-device-reads") {
    DeviceReadBenchmark.run()
    exit(0)
}
#endif

let storeIdentifierKey = "iTM.AppStore.DeviceIdentifier"
let storeIdentifier = UserDefaults.standard.string(forKey: storeIdentifierKey)
    ?? (try? ApplePackage.DeviceIdentifier.system())
    ?? ApplePackage.DeviceIdentifier.random()
UserDefaults.standard.set(storeIdentifier, forKey: storeIdentifierKey)
ApplePackage.Configuration.deviceIdentifier = storeIdentifier

DiggerManager.shared.maxConcurrentTasksCount = 32
DiggerManager.shared.timeout = 60
DiggerCache.cleanDownloadFiles()
DiggerCache.cleanDownloadTempFiles()

#if DEBUG
// Deterministic screenshots use the production error views without starting a backup.
if let index = CommandLine.arguments.firstIndex(of: "--preview-backup-error"),
   CommandLine.arguments.count > index + 1 {
    let scenario = CommandLine.arguments[index + 1]
    let samples: [String: [String]] = [
        "disk": ["备份磁盘空间不足（错误 105）。请更换备份位置或释放磁盘空间后重试。"],
        "connection": ["设备连接已断开。请重新连接 iPhone，解锁并确认信任此 Mac 后重试。"],
        "permission": ["无法写入备份位置。请检查文件夹的读写权限，或选择其他备份位置。"],
        "multiple": ["备份磁盘空间不足（错误 105）。请更换备份位置或释放磁盘空间后重试。", "无法保存备份清单，请检查磁盘连接和写入权限。"],
        "unknown": ["ERROR: Could not receive from mobilebackup2 (-1)"],
    ]
    let vm = ViewModel.shared
    let task = BackupTask(parameter: .init(udid: "preview", backupLocation: URL(fileURLWithPath: "/tmp/itm-preview-unused")))
    task.deviceDataTask.error = .unexpectedExitCode
    task.deviceDataTask.reportedErrors = samples[scenario] ?? []
    task.deviceDataTask.status = .completed
    vm.mode = .backup
    vm.deviceIdentifier = "preview"
    vm.backupTask = task
    vm.page = .backupProgress
}
if let index = CommandLine.arguments.firstIndex(of: "--preview-backup-result"),
   CommandLine.arguments.count > index + 1 {
    let scenario = CommandLine.arguments[index + 1]
    let vm = ViewModel.shared
    let task = BackupTask(parameter: .init(udid: "preview", backupLocation: URL(fileURLWithPath: "/tmp/itm-preview-unused")))
    if scenario == "preparing" {
        task.deviceDataTask.preparationStage = .responding
    } else if scenario == "transfer" {
        task.deviceDataTask.hasStartedTransfer = true
        task.deviceDataTask.hasReportedOverallProgress = true
        task.deviceDataTask.overall.totalUnitCount = 100
        task.deviceDataTask.overall.completedUnitCount = 80
    } else {
        task.deviceDataTask.status = .completed
        task.verificationStatus = scenario == "passed" ? .passed : (scenario == "failed" ? .failed : .pending)
    }
    vm.mode = .backup
    vm.deviceIdentifier = "preview"
    vm.backupTask = task
    vm.page = .backupProgress
}
if let index = CommandLine.arguments.firstIndex(of: "--preview-restore-progress"),
   CommandLine.arguments.count > index + 1 {
    let scenario = CommandLine.arguments[index + 1]
    let vm = ViewModel.shared
    let location = URL(fileURLWithPath: "/tmp/itm-preview-unused")
    let task = RestoreTask(parameter: .init(udid: "preview", mode: .replace, archiveLocation: location, archivePassword: ""))
    if scenario == "complete" || scenario == "failure" {
        task.restoreDeviceTask.status = .completed
        if scenario == "failure" { task.restoreDeviceTask.error = .unexpectedExitCode }
    } else if scenario == "transfer" {
        task.restoreDeviceTask.overall.totalUnitCount = 100
        task.restoreDeviceTask.overall.completedUnitCount = 80
    }
    vm.mode = .restore
    vm.deviceIdentifier = "preview"
    vm.restoreLocation = location.path
    vm.restoreMode = .replace
    vm.restoreTask = task
    vm.page = .restoreProgress
}
#endif
NSWindow.allowsAutomaticWindowTabbing = false

MobileTransfer.main()
