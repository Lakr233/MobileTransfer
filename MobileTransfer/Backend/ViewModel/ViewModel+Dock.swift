//
//  ViewModel+Dock.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/10/10.
//

import DockProgress
import Foundation

extension ViewModel {
    func bindProgressToDock() {
        // With @Observable, views will automatically track changes.
        // We use a timer-based approach to periodically update dock progress
        // since we no longer have objectWillChange publisher.
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            // Stop updating once task is completed
            if backupTask == nil, restoreTask == nil, applicationInstallTask == nil {
                timer.invalidate()
                return
            }
            updateProgress()
        }
    }

    @MainActor private func updateProgress() {
        if taskCompleted {
            DockProgress.style = .squircle(color: taskSuccess ? .green : .orange)
            DockProgress.progress = 1
        } else {
            DockProgress.style = .squircle(color: .accent)
            DockProgress.progress = overallProgress.fractionCompleted
        }
    }
}
