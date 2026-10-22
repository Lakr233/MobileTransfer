//
//  ViewModel+CreateTask.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/10/10.
//

import Cocoa
import Foundation
import UniformTypeIdentifiers

extension ViewModel {
    func createBackupTask() {
        assert(deviceIdentifier != nil)
        assert(mode == .backup)
        assert(!backupLocation.isEmpty)

        guard backupTask == nil else { return }
        guard let udid = deviceIdentifier else { return }

        let parameter = BackupTask.BackupTaskParameter(
            udid: udid,
            backupLocation: URL(fileURLWithPath: backupLocation),
            backupApps: backupApps,
            allowedAccounts: backupApplicationAccountAllowed,
            backupAppList: backupApplicationList
        )
        let task = BackupTask(parameter: parameter)
        Archives.trackBackup(at: parameter.backupLocation)
        backupTask = task

        bindProgressToDock()

        DispatchQueue.global(qos: .utility).async {
            task.run()
        }
    }

    func createRestoreTask() {
        assert(deviceIdentifier != nil)
        assert(mode == .restore)
        assert(restoreLocation != nil)
        assert(restoreMode != .unspecified)

        guard restoreTask == nil else { return }
        guard let udid = deviceIdentifier else { return }
        guard let restoreLocation else { return }
        guard restoreMode != .unspecified else { return }

        let task = RestoreTask(parameter: .init(
            udid: udid,
            mode: restoreMode,
            archiveLocation: URL(fileURLWithPath: restoreLocation),
            archivePassword: restorePassword
        ))
        restoreTask = task

        bindProgressToDock()

        DispatchQueue.global(qos: .utility).async {
            task.run()
        }
    }

    func createApplicationInstallTask() {
        assert(deviceIdentifier != nil)
        assert(mode == .restore)
        assert(restoreLocation != nil)
        assert(restoreApplicationsCount > 0)

        guard applicationInstallTask == nil else { return }
        guard let udid = deviceIdentifier else { return }
        guard let restoreLocation else { return }

        let task = MobileInstallTask(parameter: .init(
            udid: udid,
            archiveLocation: URL(fileURLWithPath: restoreLocation)
                .appendingPathComponent("Applications")
        ))
        applicationInstallTask = task

        bindProgressToDock()

        DispatchQueue.global(qos: .utility).async {
            task.run()
        }
    }

    func showBackupLocationInFinder() {
        let url = URL(fileURLWithPath: backupLocation)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func showRestoreBackupLocationInFinder() {
        guard let restoreLocation else { return }
        let url = URL(fileURLWithPath: restoreLocation)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func pickSaveLocation(completion: ((Bool) -> Void)? = nil) {
        guard let window = NSApp.mainWindow ?? NSApp.windows.first else {
            completion?(false)
            return
        }

        let currentURL = URL(fileURLWithPath: backupLocation)
        let currentName = currentURL.lastPathComponent

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = currentName
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Desktop")
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        panel.message = NSLocalizedString("Choose a Location to Save Backup", comment: "")

        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let newUrl = panel.url else {
                completion?(false)
                return
            }
            do {
                guard !FileManager.default.fileExists(atPath: newUrl.path) else {
                    throw CocoaError(.fileWriteFileExists)
                }
                try FileManager.default.createDirectory(
                    at: newUrl,
                    withIntermediateDirectories: false
                )
                self.backupLocation = newUrl.path
                completion?(true)
            } catch {
                NSAlert(error: error).beginSheetModal(for: window)
                completion?(false)
            }
        }
    }

    func pickRestoreArchive() {
        guard let window = NSApp.keyWindow else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = false
        panel.message = NSLocalizedString("Choose Backup Archive to Restore", comment: "")

        if let type = UTType("tech.nootag.itm.backup") {
            panel.allowedContentTypes = [type]
        } else {
            assertionFailure()
        }

        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            let info = Archives.validateRestoreArchive(at: url)
            guard info.verified else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let alert = NSAlert()
                    alert.messageText = NSLocalizedString("Invalid Archive", comment: "")
                    alert.informativeText = NSLocalizedString("The selected archive is invalid or corrupted.", comment: "")
                    alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
                    alert.alertStyle = .critical
                    alert.beginSheetModal(for: window)
                }
                return
            }
            self.restoreArchiveIsPasswordProtected = info.isEncrypted
            self.restoreApplicationsCount = info.applications
            self.restoreArchiveSystemBuildVersion = info.systemBuildVersion
            self.restoreLocation = url.path
            Archives.rememberCompletedBackup(at: url)
        }
    }

    func validateRestoreArchive(at url: URL) -> Bool {
        let info = Archives.validateRestoreArchive(at: url)
        restoreArchiveIsPasswordProtected = info.isEncrypted
        restoreApplicationsCount = info.applications
        restoreArchiveSystemBuildVersion = info.systemBuildVersion
        return info.verified
    }
}
