//
//  LicensePageView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/10/17.
//

import SwiftUI
import WindowAnimation

struct LicensePageView: View {
    @Environment(ViewModel.self) var vm

    var body: some View {
        VStack {
            if let licenseInfo = vm.licenseInfo, !vm.isLicenseTrail {
                LicenseInfoView(licenseInfo: licenseInfo)
            } else {
                ActivationView()
            }
        }
        .animation(.spring, value: vm.licenseInfo)
        .frame(width: 450)
        .modifier(WindowAnimationModifier())
    }
}
