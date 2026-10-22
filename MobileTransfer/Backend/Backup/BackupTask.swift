//
//  BackupTask.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import AppKit
import AppleMobileDeviceLibrary
import Foundation
import Observation

@Observable
class BackupTask: Identifiable {
    let id: UUID = .init()

    struct BackupTaskParameter: Codable {
        let udid: String
        let backupLocation: URL
        var backupApps: Bool = false
        var allowedAccounts: Set<String> = []
        var backupAppList: [App] = []
    }

    @ObservationIgnored private let executionFinished = DispatchGroup()
    private let ownsNewArchive: Bool
    var isCancelling = false

    let parameter: BackupTaskParameter
    let deviceDataTask: MobileBackupTask
    let applicationDataTask: MobileAppConnectTask?

    enum VerificationStatus {
        case failed
        case passed
        case pending
    }

    var verificationStatus: VerificationStatus = .pending

    var completed: Bool {
        if !deviceDataTask.completed { return false }
        return applicationDataTask?.completed ?? true
    }

    init(parameter: BackupTaskParameter) {
        self.parameter = parameter
        ownsNewArchive = (try? FileManager.default.contentsOfDirectory(atPath: parameter.backupLocation.path).isEmpty) == true
        executionFinished.enter()

        deviceDataTask = MobileBackupTask(config: .init(
            device: .init(
                udid: parameter.udid,
                deviceRecord: .init(),
                pairRecord: .init(),
                extra: [:],
                possibleNetworkAddress: []
            ),
            useNetwork: false,
            useStoreBase: parameter.backupLocation
        ))
        applicationDataTask = parameter.backupApps ? MobileAppConnectTask(
            appList: parameter.backupAppList,
            allowedAccounts: parameter.allowedAccounts,
            storeBase: parameter.backupLocation.appendingPathComponent("Applications")
        ) : nil
    }

    deinit {
        terminate()
    }

    func run() {
        assert(!Thread.isMainThread)
        defer { executionFinished.leave() }
        let usageURL = parameter.backupLocation.appendingPathComponent(".itm-app-usage.plist")
        // Incremental clones must never retain an older version's usage snapshot.
        try? FileManager.default.removeItem(at: usageURL)
        if !isCancelling,
           let snapshot = AppleMobileDeviceManager.shared.applicationUsageSnapshot(udid: parameter.udid),
           let data = try? PropertyListSerialization.data(fromPropertyList: snapshot, format: .binary, options: 0) {
            try? data.write(to: usageURL, options: .atomic)
        }
        guard !isCancelling else { return }
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            self.deviceDataTask.start()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            self.applicationDataTask?.start()
            group.leave()
        }

        group.wait()
        assert(completed)

        guard deviceDataTask.success, !isCancelling else { return }

        let backupLocation = parameter.backupLocation
        let info = Archives.validateRestoreArchive(at: backupLocation)
        if info.verified {
            try? FileManager.default.removeItem(
                at: backupLocation.appendingPathComponent(Archives.pendingMarkerName)
            )
            Archives.rememberCompletedBackup(at: backupLocation)
        }
        DispatchQueue.main.asyncAndWait {
            self.verificationStatus = info.verified ? .passed : .failed
        }

        if let data = try? PropertyListEncoder().encode(parameter) {
            try? data.write(to: parameter
                .backupLocation
                .appendingPathComponent("BackupManifest.plist"))
        }
    }

    /// Wait for every writer before moving this run's newly created archive to Trash.
    /// Existing archives selected for retry/resume are retained.
    func cancelAndCleanUp(completion: @escaping (Error?) -> Void) {
        guard !isCancelling else { return }
        isCancelling = true
        terminate()
        DispatchQueue.global(qos: .utility).async {
            self.executionFinished.wait()
            DispatchQueue.main.async {
                guard self.ownsNewArchive else { completion(nil); return }
                NSWorkspace.shared.recycle([self.parameter.backupLocation]) { _, error in
                    DispatchQueue.main.async { completion(error) }
                }
            }
        }
    }

    func terminate() {
        deviceDataTask.terminate()
        applicationDataTask?.terminate()
    }
}

#if DEBUG
extension BackupTask {
    static func verifyCancellation() -> Bool {
        for existing in [false, true] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mobiletransfer")
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
                if existing { try Data("keep".utf8).write(to: url.appendingPathComponent("existing-data")) }
            } catch { return false }
            defer { try? FileManager.default.removeItem(at: url) }
            let task = BackupTask(parameter: .init(udid: "test", backupLocation: url))
            var finished = false
            var failed = false
            task.cancelAndCleanUp { error in
                failed = error != nil
                finished = true
            }
            DispatchQueue.global(qos: .utility).async { task.run() }
            let deadline = Date().addingTimeInterval(10)
            while !finished && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            guard finished, !failed,
                  FileManager.default.fileExists(atPath: url.path) == existing else { return false }
        }
        return true
    }
}
#endif
