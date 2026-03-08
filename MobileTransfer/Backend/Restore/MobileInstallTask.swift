//
//  MobileInstallTask.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/27.
//

import AuxiliaryExecute
import Foundation
import Observation
import ZIPFoundation

@Observable
class MobileInstallTask: Identifiable {
    let id: UUID = .init()

    struct ApplicationInstallTaskPatameter: Codable {
        let udid: String
        let archiveLocation: URL
    }

    let parameter: ApplicationInstallTaskPatameter

    var cancelled: Bool = false

    struct Log: Identifiable, Equatable {
        var id: UUID = .init()
        let date: Date = .init()
        let text: String
        var isError: Bool = false
    }

    var output: [Log] = []

    var error: String?
    var failedList: [String] = []
    var isWaitingForDeviceToConnect = false
    var progress: Progress = .init()
    var completed: Bool = false

    var success: Bool {
        error == nil && failedList.isEmpty
    }

    var workerProcessIdentifier: [Int] = []

    init(parameter: ApplicationInstallTaskPatameter) {
        self.parameter = parameter
    }

    deinit {
        terminate()
    }

    func run() {
        assert(!Thread.isMainThread)

        requiresMainThread { self.completed = false }
        defer { requiresMainThread { self.completed = true } }

        requiresMainThread {
            self.progress.totalUnitCount = 1
            self.progress.completedUnitCount = 0
        }
        defer { requiresMainThread { self.progress.completedUnitCount = self.progress.totalUnitCount } }

        decodeOutput("\(Self.mobileInstallExecutable)", isError: false)
        decodeOutput("Core Version: \(Self.mobileInstallVersion)", isError: false)
        defer { if let error { decodeOutput(error, isError: true) } }

        requiresMainThread { self.isWaitingForDeviceToConnect = true }
        defer { requiresMainThread { self.isWaitingForDeviceToConnect = false } }

        var deviceConnected = false
        for _ in 0 ... 120 where !deviceConnected && !cancelled {
            defer { sleep(1) }
            AppleMobileDeviceManager.shared.requireDevice(
                udid: parameter.udid,
                connection: .usb
            ) { device in
                guard let device else { return }
                AppleMobileDeviceManager.shared.requireLockdownClient(
                    device: device,
                    name: "MobileTransfer-Installer",
                    handshake: true
                ) { client in
                    guard client != nil else { return }
                    deviceConnected = true
                }
            }
        }

        guard !cancelled else {
            requiresMainThread { self.error = NSLocalizedString("Cancelled", comment: "") }
            return
        }

        guard deviceConnected else {
            requiresMainThread { self.error = NSLocalizedString("Unable to connect to device", comment: "") }
            return
        }

        requiresMainThread { self.isWaitingForDeviceToConnect = false }

        var apps: [URL] = []
        do {
            try? FileManager.default.contentsOfDirectory(
                at: parameter.archiveLocation,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
            .filter { $0.pathExtension == "ipa" }
            .forEach { apps.append($0) }
        }

        requiresMainThread {
            self.progress.totalUnitCount = Int64(apps.count)
            self.progress.completedUnitCount = 0
        }

        decodeOutput(String(format: NSLocalizedString("Installing %d apps...", comment: ""), apps.count), isError: false)

        var installedApplicationBundleIdentifiers = Set<String>()
        let listApps = AppleMobileDeviceManager.shared.listApplications(udid: parameter.udid, connection: .usb)
        if let listApps {
            for (bundleIdentifier, _) in listApps {
                installedApplicationBundleIdentifiers.insert(bundleIdentifier.lowercased())
            }
        }

        let group = DispatchGroup()
        let sem = DispatchSemaphore(value: 3)
        for app in apps {
            group.enter()
            sem.wait()
            DispatchQueue.global().async {
                autoreleasepool {
                    defer {
                        requiresMainThread { self.progress.completedUnitCount += 1 }
                        sem.signal()
                        group.leave()
                    }
                    guard !self.cancelled else { return }
                    let bundleIdentifier = self.findBundleIdentifier(app).lowercased()
                    guard !bundleIdentifier.isEmpty else {
                        assertionFailure()
                        return
                    }
                    guard !self.cancelled else { return }
                    if installedApplicationBundleIdentifiers.contains(bundleIdentifier) {
                        self.decodeOutput(String(format: NSLocalizedString("Skipped due to already installed %@", comment: ""), app.lastPathComponent), isError: false)
                    } else {
                        self.installApp(app, useUpgrade: false)
                    }
                }
            }
        }
        group.wait()

        guard !cancelled else {
            requiresMainThread { self.error = NSLocalizedString("Cancelled", comment: "") }
            return
        }
        decodeOutput(NSLocalizedString("Completed", comment: ""), isError: false)
    }

    func installApp(_ app: URL, useUpgrade: Bool) {
        guard !cancelled else { return }

        decodeOutput(String(format: NSLocalizedString("Requested %@", comment: ""), app.lastPathComponent), isError: false)
        let setPid: (pid_t) -> Void = { pid in
            requiresMainThread { self.workerProcessIdentifier.append(Int(pid)) }
        }
        let output: (String) -> Void = { output in print(output) }

        let recp = AuxiliaryExecute.spawn(
            command: Self.mobileInstallExecutable,
            args: [
                "-u", parameter.udid,
                useUpgrade ? "upgrade" : "install", app.path,
            ],
            timeout: -1,
            setPid: setPid,
            output: output
        )
        requiresMainThread { self.workerProcessIdentifier.removeAll { $0 == recp.pid } }

        guard !cancelled else { return }

        let finalOutput = if recp.exitCode == 0 {
            String(format: NSLocalizedString("Install Completed: %@", comment: ""), app.lastPathComponent)
        } else {
            String(format: NSLocalizedString("Install Failed %@: %d", comment: ""), app.lastPathComponent, recp.exitCode)
        }
        requiresMainThread {
            self.decodeOutput(finalOutput, isError: recp.exitCode != 0)
            if recp.exitCode != 0 {
                self.failedList.append(app.lastPathComponent)
                let errorText = recp.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                if !errorText.isEmpty { self.decodeOutput(errorText, isError: true) }
            }
        }
    }

    func findBundleIdentifier(_ app: URL) -> String {
        assert(!Thread.isMainThread)
        do {
            let zip = try Archive(url: app, accessMode: .read)

            var ans = ""
            for entry in zip where ans.isEmpty {
                guard entry.type == .file else { continue }
                guard entry.path.hasSuffix(".app/Info.plist") else { continue }
                let sem = DispatchSemaphore(value: 0)
                do {
                    // 32 mb for the buffer size should be enough for the Info.plist to be read entirely
                    _ = try zip.extract(entry, bufferSize: 32 * 1024 * 1024) { data in
                        defer { sem.signal() }
                        guard let plist = try? PropertyListSerialization.propertyList(
                            from: data,
                            options: [],
                            format: nil
                        ) as? [String: Any] else {
                            assertionFailure()
                            return
                        }
                        guard let bundleIdentifier = plist["CFBundleIdentifier"] as? String else {
                            assertionFailure()
                            return
                        }
                        ans = bundleIdentifier
                    }
                } catch {
                    sem.signal()
                }
                sem.wait()
            }

            return ans
        } catch {
            return ""
        }
    }

    func terminate() {
        cancelled = true
        for pid in workerProcessIdentifier {
            kill(Int32(pid), SIGKILL)
        }
    }

    private func decodeOutput(_ output: String, isError: Bool) {
        decodeLine(output, isError: isError)
    }

    private func decodeLine(_ line: String, isError: Bool) {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        NSLog("[Install] \(id) \(line)")
        requiresMainThread { self.output.append(.init(text: line, isError: isError)) }
    }
}

extension MobileInstallTask {
    static let mobileInstallExecutable = Bundle.main.url(forAuxiliaryExecutable: "MobileInstall")!.path
    static let mobileInstallVersion: String = {
        var stdout = AuxiliaryExecute.spawn(
            command: mobileInstallExecutable,
            args: ["-v"]
        ).stdout
        if stdout.hasPrefix("ideviceinstaller") {
            stdout.removeFirst("ideviceinstaller".count)
        }
        stdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return stdout
    }()
}
