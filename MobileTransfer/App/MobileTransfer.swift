//
//  MobileTransfer.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/10/23.
//

import SwiftUI

struct MobileTransfer: SwiftUI.App {
    @State var vm = ViewModel.shared

    @State var progress = false
    @State var openLicensePage = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .opacity(openLicensePage ? 0 : 1)
                .animation(.spring, value: openLicensePage)
                .onAppear { closeOtherWindows() }
                .onAppear { if vm.licenseInfo == nil { openLicensePage = true } }
                .sheet(isPresented: $openLicensePage) {
                    LicensePageView()
                }
                .onAppear { checkLicenseOpen(isOnAppear: true) }
                .onChange(of: openLicensePage) { checkLicenseOpen() }
                .onChange(of: vm.page) { checkLicenseOpen() }
                .sheet(isPresented: $progress) {
                    ProgressView()
                        .interactiveDismissDisabled()
                        .frame(width: 333, height: 222)
                }
                .frame(
                    minWidth: 666, idealWidth: 666, maxWidth: .infinity,
                    minHeight: 444, idealHeight: 444, maxHeight: .infinity,
                    alignment: .center
                )
                .environment(vm)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands { commands }
    }

    func checkLicenseOpen(isOnAppear: Bool = false) {
        guard !openLicensePage else { return }
        // allow in progress usage even after trail expire
        guard vm.page == .welcome else { return }
        guard vm.licenseInfo != nil else {
            openLicensePage = true
            return
        }
        if isOnAppear, vm.isLicenseTrail {
            openLicensePage = true
            return
        }
    }

    func closeOtherWindows() {
        let windows = NSApp.windows
        for window in windows {
            if window != NSApp.keyWindow, NSApp.windows.count > 1 {
                window.close()
            } else {
                window.center()
            }
        }
    }
}
