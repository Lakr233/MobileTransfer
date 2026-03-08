//
//  BackgroundView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import ColorfulX
import SwiftUI

struct BackgroundView: View {
    @Environment(ViewModel.self) var vm

    var body: some View {
        ColorfulView(
            color: vm.backgroundColor,
            speed: .constant(vm.backgroundColorAnimated ? 0.5 : 0),
            transitionSpeed: .constant(4)
        )
        .opacity(0.1)
        .ignoresSafeArea()
    }
}

private struct BackgroundThemeColor: ColorfulColors {
    var colors: [ColorfulX.ColorElement] {
        [
            .welcomeColorMain,
            .welcomeColorSecondary,
            .welcomeColorMain,
            .welcomeColorSecondary,
            .clear,
            .clear,
            .clear,
            .clear,
            .clear,
            .clear,
            .clear,
            .clear,
        ]
    }
}

private struct BackgroundActionMenuColor: ColorfulColors {
    var colors: [ColorElement] {
        ColorfulPreset.lavandula.colors
    }
}

private struct BackgroundFinalConfirmationColor: ColorfulColors {
    var colors: [ColorElement] {
        ColorfulPreset.ocean.colors
    }
}

private struct BackgroundTaskProgressColor: ColorfulColors {
    var colors: [ColorElement] {
        ColorfulPreset.ocean.colors
    }
}

private extension ViewModel {
    var backgroundColor: ColorfulColors {
        switch page {
        case .welcome, .findDevice:
            BackgroundThemeColor()
        case .actionMenu:
            BackgroundActionMenuColor()
        case .prepareBackup, .prepareRestore:
            BackgroundThemeColor()
        case .backupProgress, .restoreProgress:
            BackgroundTaskProgressColor()
        case .installApplication:
            BackgroundActionMenuColor()
        }
    }

    var backgroundColorAnimated: Bool {
        switch page {
        case .welcome:
            false
        case .actionMenu:
            false
        case .findDevice:
            true
        case .prepareBackup:
            false
        case .prepareRestore:
            false
        case .backupProgress, .restoreProgress, .installApplication:
            true
        }
    }
}
