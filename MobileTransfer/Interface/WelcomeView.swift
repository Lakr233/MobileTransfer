import SwiftUI

struct WelcomeView: View {
    @Environment(ViewModel.self) private var vm
    @State private var latestBackupDate: Date?
    @State private var loadingHistory = true

    private var restoreDetail: LocalizedStringKey {
        if loadingHistory { return "Finding backups…" }
        if let latestBackupDate {
            return "Latest backup: \(latestBackupDate.formatted(date: .abbreviated, time: .shortened))"
        }
        return "No completed backup found"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 45, weight: .light))
                .foregroundStyle(.primary)
                .frame(width: 80, height: 80)
                .itmGlassSurface(cornerRadius: 24)

            Text("iTM")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .padding(.top, 16)

            Text("iOS TimeMachine")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            Link("@Sunbelife · weibo.com/x1nyang", destination: URL(string: "https://weibo.com/x1nyang")!)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            actions
                .padding(.top, 25)
                .frame(maxWidth: 440)

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            vm.resetAll()
            loadingHistory = true
            DispatchQueue.global(qos: .utility).async {
                let latest = Archives.availableBackups().first?.date
                DispatchQueue.main.async {
                    latestBackupDate = latest
                    loadingHistory = false
                }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                actionButtons
            }
        } else {
            actionButtons
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            WelcomeAction(
                symbol: "arrow.up.to.line",
                title: "Backup Device",
                detail: "Download device data and archive to selected destination"
            ) {
                vm.mode = .backup
                vm.page = .findDevice
            }

            WelcomeAction(
                symbol: "arrow.down.to.line",
                title: "Restore Device",
                detail: restoreDetail
            ) {
                vm.mode = .restore
                vm.page = .findDevice
            }
        }
    }
}

private struct WelcomeAction: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .medium))
                    .frame(width: 42, height: 42)
                    .background(.primary.opacity(0.06))
                    .clipShape(.rect(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .padding(15)
            .itmGlassSurface(cornerRadius: 20, interactive: true)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
