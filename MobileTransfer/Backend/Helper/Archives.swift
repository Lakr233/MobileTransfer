//
//  Archives.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/10/10.
//

import Cocoa
import Darwin
import Foundation
import UniformTypeIdentifiers

enum Archives {
    static let incrementalMarkerName = ".itm-incremental-base.plist"
    static let pendingMarkerName = ".itm-pending"
    private static let historyKey = "tech.nootag.itm.backupHistoryPaths"

    struct BackupRecord: Identifiable {
        let url: URL
        let date: Date
        let deviceIdentifier: String
        let deviceName: String
        let modelName: String
        let systemVersion: String

        var displayName: String {
            deviceName == modelName || deviceName.isEmpty ? modelName : [deviceName, modelName].filter { !$0.isEmpty }.joined(separator: " · ")
        }

        var id: String { url.path }
    }

    static func rememberCompletedBackup(at url: URL) {
        guard backupRecord(at: url) != nil else { return }
        trackBackup(at: url)
    }

    static func trackBackup(at url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
        let path = url.standardizedFileURL.path
        if !paths.contains(path) {
            paths.append(path)
            UserDefaults.standard.set(paths, forKey: historyKey)
        }
    }

    static func availableBackups(for deviceIdentifier: String? = nil) -> [BackupRecord] {
        let paths = Set(UserDefaults.standard.stringArray(forKey: historyKey) ?? [])
        return paths.compactMap { backupRecord(at: URL(fileURLWithPath: $0)) }
            .filter {
                guard let deviceIdentifier else { return true }
                return $0.deviceIdentifier.caseInsensitiveCompare(deviceIdentifier) == .orderedSame
            }
            .sorted { $0.date > $1.date }
    }

    /// Discovery only: validate the selected archive before preparing any update.
    static func backupCandidates(for deviceIdentifier: String, searchComputer: Bool) -> [URL] {
        var paths = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
        if searchComputer {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
            process.arguments = ["kMDItemFSName == '*.mobiletransfer'cd"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            if (try? process.run()) != nil {
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    paths += String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
                }
            }
        }
        return Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL }).filter { url in
            guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Info.plist")) as? [String: Any],
                  let identifier = (info["Target Identifier"] as? String) ?? (info["Unique Identifier"] as? String)
            else { return false }
            return identifier.caseInsensitiveCompare(deviceIdentifier) == .orderedSame
        }.sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return left > right
        }
    }

    static func latestBackupSource(in folder: URL, deviceIdentifier: String) throws -> BackupSource? {
        let children = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles]
        )
        let latest = children.filter {
            (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true
        }.compactMap { backupRecord(at: $0) }
            .filter { $0.deviceIdentifier.caseInsensitiveCompare(deviceIdentifier) == .orderedSame }
            .max { $0.date < $1.date }
        guard let latest else { return nil }
        return try inspectBackupSource(at: latest.url, deviceIdentifier: deviceIdentifier)
    }

    static func newBackupURL(in folder: URL, deviceName: String) -> URL {
        let name = deviceName.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let base = "\(name) - \(formatter.string(from: Date()))"
        var url = folder.appendingPathComponent(base).appendingPathExtension("mobiletransfer")
        var index = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base)-\(index)").appendingPathExtension("mobiletransfer")
            index += 1
        }
        return url
    }

    private static func backupRecord(at url: URL) -> BackupRecord? {
        guard url.pathExtension.lowercased() == "mobiletransfer",
              !FileManager.default.fileExists(atPath: url.appendingPathComponent(pendingMarkerName).path),
              let info = NSDictionary(contentsOf: url.appendingPathComponent("Info.plist")) as? [String: Any],
              let identifier = (info["Target Identifier"] as? String) ?? (info["Unique Identifier"] as? String),
              let status = NSDictionary(contentsOf: url.appendingPathComponent("Status.plist")) as? [String: Any],
              (status["SnapshotState"] as? String)?.lowercased() == "finished"
        else { return nil }
        let date = (status["Date"] as? Date)
            ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            ?? .distantPast
        let deviceName = info["Device Name"] as? String ?? ""
        let productType = info["Product Type"] as? String ?? ""
        let modelName = ConnectedDevice.modelNames[productType] ?? (productType.isEmpty ? "iPhone" : productType)
        return BackupRecord(url: url, date: date, deviceIdentifier: identifier,
                            deviceName: deviceName, modelName: modelName,
                            systemVersion: info["Product Version"] as? String ?? "")
    }

    enum BackupSourceMode {
        case incremental
        case resumeIncremental
        case retryFull
    }

    struct BackupSource {
        let url: URL
        let mode: BackupSourceMode
    }

    enum BackupSourceError: LocalizedError {
        case invalid
        case wrongDevice
        case unsupportedVolume
        case inUse

        var errorDescription: String? {
            switch self {
            case .invalid: return NSLocalizedString("This backup cannot be continued.", comment: "")
            case .wrongDevice: return NSLocalizedString("This backup belongs to another device.", comment: "")
            case .unsupportedVolume: return NSLocalizedString("Version history requires an APFS volume.", comment: "")
            case .inUse: return NSLocalizedString("This backup is already in use.", comment: "")
            }
        }
    }

    static func inspectBackupSource(at url: URL, deviceIdentifier: String) throws -> BackupSource {
        guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Info.plist")) as? [String: Any],
              let identifier = (info["Target Identifier"] as? String) ?? (info["Unique Identifier"] as? String),
              let status = NSDictionary(contentsOf: url.appendingPathComponent("Status.plist")) as? [String: Any],
              let state = status["SnapshotState"] as? String
        else { throw BackupSourceError.invalid }
        guard identifier.caseInsensitiveCompare(deviceIdentifier) == .orderedSame else {
            throw BackupSourceError.wrongDevice
        }
        let lockPath = url.appendingPathComponent(".itm.lock").path
        if FileManager.default.fileExists(atPath: lockPath) {
            let descriptor = open(lockPath, O_RDONLY | O_NOFOLLOW)
            guard descriptor >= 0 else { throw BackupSourceError.invalid }
            defer { close(descriptor) }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                throw BackupSourceError.inUse
            }
            flock(descriptor, LOCK_UN)
        }

        let hasManifest = ["Manifest.plist", "Manifest.db"].allSatisfy { name in
            let path = url.appendingPathComponent(name).path
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber
            return (size?.int64Value ?? 0) > 0
        }
        switch state.lowercased() {
        case "finished" where hasManifest && hasIncrementalMarker(at: url)
            && FileManager.default.fileExists(atPath: url.appendingPathComponent(pendingMarkerName).path):
            return BackupSource(url: url, mode: .resumeIncremental)
        case "finished" where hasManifest
            && !FileManager.default.fileExists(atPath: url.appendingPathComponent(pendingMarkerName).path):
            guard validateRestoreArchive(at: url).verified else {
                throw BackupSourceError.invalid
            }
            return BackupSource(url: url, mode: .incremental)
        case "uploading" where hasManifest && hasIncrementalMarker(at: url):
            return BackupSource(url: url, mode: .resumeIncremental)
        case "uploading":
            return BackupSource(url: url, mode: .retryFull)
        default:
            throw BackupSourceError.invalid
        }
    }

    static func makeIncrementalVersion(from source: URL, deviceName: String) throws -> URL {
        let lockPath = source.appendingPathComponent(".itm.lock").path
        let archiveLock = open(lockPath, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard archiveLock >= 0 else { throw BackupSourceError.invalid }
        defer { close(archiveLock) }
        guard flock(archiveLock, LOCK_EX | LOCK_NB) == 0 else {
            throw BackupSourceError.inUse
        }

        let destination = newBackupURL(in: source.deletingLastPathComponent(), deviceName: deviceName)

        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        do {
            try Data().write(to: destination.appendingPathComponent(pendingMarkerName))
            try cloneBackupContents(from: source, to: destination)
            let marker = ["BaseArchive": source.lastPathComponent]
            let markerData = try PropertyListSerialization.data(
                fromPropertyList: marker, format: .xml, options: 0
            )
            try markerData.write(
                to: destination.appendingPathComponent(incrementalMarkerName),
                options: .atomic
            )
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    static func hasIncrementalMarker(at url: URL) -> Bool {
        let marker = url.appendingPathComponent(incrementalMarkerName)
        guard let info = NSDictionary(contentsOf: marker) as? [String: Any],
              let base = info["BaseArchive"] as? String else { return false }
        return !base.isEmpty
    }

    private static func cloneBackupContents(from source: URL, to destination: URL) throws {
        for item in try FileManager.default.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        ) {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { throw BackupSourceError.invalid }
            if values.isDirectory == true {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
                try cloneBackupContents(from: item, to: target)
            } else if values.isRegularFile == true {
                guard clonefile(item.path, target.path, 0) == 0 else {
                    if errno == ENOTSUP || errno == EXDEV {
                        throw BackupSourceError.unsupportedVolume
                    }
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
            } else {
                throw BackupSourceError.invalid
            }
        }
    }

    struct ArchiveInfo {
        let url: URL
        let verified: Bool
        let deviceIdentifier: String
        let isEncrypted: Bool
        let systemBuildVersion: String
        let applications: Int
        let failureReason: String?

        init(
            url: URL,
            verified: Bool,
            deviceIdentifier: String,
            isEncrypted: Bool,
            systemBuildVersion: String,
            applications: Int,
            failureReason: String?
        ) {
            self.url = url
            self.verified = verified
            self.deviceIdentifier = deviceIdentifier
            self.isEncrypted = isEncrypted
            self.systemBuildVersion = systemBuildVersion
            self.applications = applications
            self.failureReason = failureReason
        }

        static func broken(at: URL, reason: String) -> ArchiveInfo {
            ArchiveInfo(
                url: at,
                verified: false,
                deviceIdentifier: "",
                isEncrypted: false,
                systemBuildVersion: "",
                applications: 0,
                failureReason: reason
            )
        }
    }
}

extension Archives {
    static func beginVerification() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true

        if let type = UTType("tech.nootag.itm.backup") {
            panel.allowedContentTypes = [type]
        } else {
            assertionFailure()
        }

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        let info = validateRestoreArchive(at: url)
        if info.verified {
            presentArchiveValid(info: info)
        } else {
            presentArchiveBroken(info: info)
        }
    }

    static func convertFromBBackupp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true

        let response = panel.runModal()
        guard response == .OK, let selectedURL = panel.url else { return }

        let devicePlist = selectedURL.appendingPathComponent("Device.plist")
        guard let deviceData = try? Data(contentsOf: devicePlist) else {
            presentConvertFailed(info: NSLocalizedString("Unable to read from Device.plist", comment: ""))
            return
        }

        let device = try? PropertyListDecoder().decode(Device.self, from: deviceData)
        guard let device else {
            presentConvertFailed(info: NSLocalizedString("Unable to decode Device.plist", comment: ""))
            return
        }

        let udid = device.udid
        guard !udid.isEmpty else {
            presentConvertFailed(info: NSLocalizedString("UDID is empty", comment: ""))
            return
        }

        let backupLocationWithUDID = selectedURL.appendingPathComponent(udid)
        let info = validateRestoreArchive(at: backupLocationWithUDID)
        guard info.verified else {
            presentConvertFailed(info: String(format:
                NSLocalizedString("Unable to validate archive at %@: %@", comment: ""),
                backupLocationWithUDID.path,
                info.failureReason ?? NSLocalizedString("Unknown error", comment: "")))
            return
        }

        let contents = try? FileManager.default.contentsOfDirectory(atPath: backupLocationWithUDID.path)
        guard var contents else {
            presentConvertFailed(info: NSLocalizedString("Unable to list contents of backup location", comment: ""))
            return
        }
        contents = contents
            .filter { !$0.hasPrefix("._") }
            .filter { $0 != ".DS_Store" }

        guard !contents.contains(where: { FileManager.default.fileExists(atPath: selectedURL.appendingPathComponent($0).path) }) else {
            presentConvertFailed(info: NSLocalizedString("File conflict with convert", comment: ""))
            return
        }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Convert BBackupp Archive", comment: "")
        alert.informativeText = String(format:
            NSLocalizedString("Convert BBackupp archive for %@ to iTM format?", comment: ""),
            device.deviceName)
        alert.addButton(withTitle: NSLocalizedString("Convert In Place", comment: ""))
        alert.buttons.first?.hasDestructiveAction = true
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.alertStyle = .warning

        let resp = alert.runModal()
        guard resp == .alertFirstButtonReturn else { return }

        var errors: [Error] = []
        for item in contents {
            do {
                let src = backupLocationWithUDID.appendingPathComponent(item)
                let dst = selectedURL.appendingPathComponent(item)
                try FileManager.default.moveItem(at: src, to: dst)
            } catch {
                errors.append(error)
            }
        }
        do {
            try FileManager.default.removeItem(at: backupLocationWithUDID)
        } catch {
            errors.append(error)
        }

        guard errors.isEmpty else {
            presentConvertFailed(info: String(format:
                NSLocalizedString("Failed to operate files: %@", comment: ""),
                errors.first?.localizedDescription ?? ""))
            return
        }

        // because of the sandbox we can only put items inside this directory
        let name = selectedURL
            .deletingPathExtension()
            .lastPathComponent
        let mobiletransfer = selectedURL
            .appendingPathComponent(name)
            .appendingPathExtension(".mobiletransfer")

        do {
            var contents = try FileManager.default.contentsOfDirectory(atPath: selectedURL.path)
            contents = contents
                .filter { !$0.hasPrefix("._") }
                .filter { $0 != ".DS_Store" }
            try FileManager.default.createDirectory(at: mobiletransfer, withIntermediateDirectories: true)
            for item in contents {
                let src = selectedURL.appendingPathComponent(item)
                let dst = mobiletransfer.appendingPathComponent(item)
                try FileManager.default.moveItem(at: src, to: dst)
            }
        } catch {
            presentConvertFailed(info: error.localizedDescription)
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([mobiletransfer])

        let newInfo = validateRestoreArchive(at: mobiletransfer)
        if newInfo.verified {
            presentArchiveValid(info: newInfo)
        } else {
            presentArchiveBroken(info: newInfo)
        }
    }

    static func validateRestoreArchive(at url: URL) -> ArchiveInfo {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return .broken(at: url, reason: NSLocalizedString("File not found", comment: ""))
        }
        guard isDir.boolValue else {
            return .broken(at: url, reason: NSLocalizedString("Selected file is not a directory", comment: ""))
        }

        let infoPlist = url.appendingPathComponent("Info.plist")
        guard FileManager.default.fileExists(atPath: infoPlist.path) else {
            return .broken(at: url, reason: NSLocalizedString("Info.plist not found", comment: ""))
        }
        guard let info = NSDictionary(contentsOf: infoPlist) as? [String: Any] else {
            return .broken(at: url, reason: NSLocalizedString("Info.plist not readable", comment: ""))
        }
        guard let systemBuildVersion = info["Build Version"] as? String else {
            return .broken(at: url, reason: NSLocalizedString("Unable to determine system build version", comment: ""))
        }
        guard let deviceIdentifier = info["Unique Identifier"] as? String else {
            return .broken(at: url, reason: NSLocalizedString("Unable to determine device identifier", comment: ""))
        }

        let statusPlist = url.appendingPathComponent("Status.plist")
        guard FileManager.default.fileExists(atPath: statusPlist.path) else {
            return .broken(at: url, reason: NSLocalizedString("Status.plist not found", comment: ""))
        }

        guard let status = NSDictionary(contentsOf: statusPlist) as? [String: Any] else {
            return .broken(at: url, reason: NSLocalizedString("Status.plist not readable", comment: ""))
        }
        guard let snapshotState = status["SnapshotState"] as? String else {
            return .broken(at: url, reason: NSLocalizedString("Unable to determine snapshot status", comment: ""))
        }
        guard snapshotState.lowercased() == "finished" else {
            return .broken(at: url, reason: NSLocalizedString("Snapshot not finished", comment: ""))
        }

        let manifestPlist = url.appendingPathComponent("Manifest.plist")
        guard FileManager.default.fileExists(atPath: manifestPlist.path) else {
            return .broken(at: url, reason: NSLocalizedString("Manifest.plist not found", comment: ""))
        }
        guard let manifest = NSDictionary(contentsOf: manifestPlist) as? [String: Any] else {
            return .broken(at: url, reason: NSLocalizedString("Manifest.plist not readable", comment: ""))
        }
        let manifestDatabase = url.appendingPathComponent("Manifest.db")
        let databaseSize = (try? FileManager.default.attributesOfItem(atPath: manifestDatabase.path)[.size]) as? NSNumber
        guard (databaseSize?.int64Value ?? 0) > 0 else {
            return .broken(at: url, reason: NSLocalizedString("Manifest.db not found", comment: ""))
        }
        let restoreArchiveIsPasswordProtected = manifest["IsEncrypted"] as? Bool ?? false

        let url = url.appendingPathComponent("Applications")
        let restoreApplicationsCount = (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.count ?? 0

        return .init(
            url: url,
            verified: true,
            deviceIdentifier: deviceIdentifier,
            isEncrypted: restoreArchiveIsPasswordProtected,
            systemBuildVersion: systemBuildVersion,
            applications: restoreApplicationsCount,
            failureReason: nil
        )
    }
}

extension Archives {
    static func presentArchiveValid(info: ArchiveInfo) {
        assert(info.verified)

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Verified Archive", comment: "")
        if info.applications > 0 {
            alert.informativeText = String(format:
                NSLocalizedString("The selected archive looks validate and contains %d applications.", comment: ""),
                info.applications)
        } else {
            alert.informativeText = NSLocalizedString("The selected archive looks validate.", comment: "")
        }
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.alertStyle = .informational
        alert.runModal()
    }

    static func presentArchiveBroken(info: ArchiveInfo) {
        assert(!info.verified)

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Invalid Archive", comment: "")
        if let reason = info.failureReason, !reason.isEmpty {
            alert.informativeText = String(
                format: NSLocalizedString("The selected archive is invalid or corrupted. %@", comment: ""),
                reason
            )
        } else {
            alert.informativeText = NSLocalizedString("The selected archive is invalid or corrupted.", comment: "")
        }
        alert.addButton(withTitle: NSLocalizedString("Move to Trash", comment: ""))
        alert.buttons.first?.hasDestructiveAction = true
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.alertStyle = .critical
        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
            try? FileManager.default.trashItem(at: info.url, resultingItemURL: nil)
        }
    }

    static func presentConvertFailed(info: String) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Convert Failed", comment: "")
        alert.informativeText = info
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.alertStyle = .critical
        alert.runModal()
    }

    enum MigrateError: Error {
        case cancelled
        case unableToVerifyBackup
        case deviceIdentifierMismatch
        case other(Error)

        var localizedDescription: String {
            switch self {
            case .cancelled:
                NSLocalizedString("Cancelled", comment: "")
            case .unableToVerifyBackup:
                NSLocalizedString("Unable to verify backup", comment: "")
            case .deviceIdentifierMismatch:
                NSLocalizedString("Unable to load checkpoint from another device", comment: "")
            case let .other(error):
                error.localizedDescription
            }
        }
    }

    static func migrateTo(location: URL, completion: @escaping (Result<Void, MigrateError>) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true

        if let type = UTType("tech.nootag.itm.backup") {
            panel.allowedContentTypes = [type]
        } else {
            assertionFailure()
        }

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            completion(.failure(.cancelled))
            return
        }

        let info = validateRestoreArchive(at: url)
        guard info.verified else {
            completion(.failure(.unableToVerifyBackup))
            return
        }

//      works with increment backup by test, so allow user to do this
//      guard info.deviceIdentifier == udid else {
//          completion(.failure(.deviceIdentifierMismatch))
//          return
//      }

        DispatchQueue.global().async {
            migrateEx(fromLocation: url, toLocation: location, completion: completion)
        }
    }

    private static func migrateEx(
        fromLocation: URL,
        toLocation: URL,
        completion: @escaping (Result<Void, MigrateError>) -> Void
    ) {
        var executeError: MigrateError?
        defer {
            sleep(1)
            DispatchQueue.main.async {
                if let executeError {
                    completion(.failure(executeError))
                } else {
                    completion(.success(()))
                }
            }
        }

        do {
            let content = try FileManager.default.contentsOfDirectory(atPath: fromLocation.path)
            for item in content where !item.hasPrefix(".") {
                let src = fromLocation.appendingPathComponent(item)
                let dst = toLocation.appendingPathComponent(item)
                try linkOrCopyItem(at: src, to: dst)
            }
        } catch {
            executeError = .other(error)
        }
    }

    private static func linkOrCopyItem(at src: URL, to dst: URL) throws {
        do {
            try FileManager.default.linkItem(at: src, to: dst)
        } catch {
            try FileManager.default.copyItem(at: src, to: dst)
        }
    }
}
