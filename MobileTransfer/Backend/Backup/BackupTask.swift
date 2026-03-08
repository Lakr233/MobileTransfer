//
//  BackupTask.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import Foundation
import Observation

@Observable
class BackupTask: Identifiable {
    let id: UUID = .init()

    struct BackupTaskParameter: Codable {
        let udid: String
        let backupLocation: URL
        let backupApps: Bool
        let allowedAccounts: Set<String>
        let backupAppList: [App]
    }

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
        if let applicationDataTask {
            if !applicationDataTask.completed { return false }
        }
        return true
    }

    init(parameter: BackupTaskParameter) {
        self.parameter = parameter

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
        if parameter.backupApps {
            applicationDataTask = MobileAppConnectTask(
                appList: parameter.backupAppList,
                allowedAccounts: parameter.allowedAccounts,
                storeBase: parameter.backupLocation.appendingPathComponent("Applications")
            )
        } else {
            applicationDataTask = nil
        }
    }

    deinit {
        terminate()
    }

    func run() {
        assert(!Thread.isMainThread)
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

        let backupLocation = parameter.backupLocation
        let info = Archives.validateRestoreArchive(at: backupLocation)
        DispatchQueue.main.asyncAndWait {
            self.verificationStatus = info.verified ? .passed : .failed
        }

        if let data = try? PropertyListEncoder().encode(parameter) {
            try? data.write(to: parameter
                .backupLocation
                .appendingPathComponent("BackupManifest.plist"))
        }
    }

    func terminate() {
        deviceDataTask.terminate()
        applicationDataTask?.terminate()
    }
}
