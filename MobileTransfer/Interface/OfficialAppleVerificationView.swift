import SwiftUI
import WebKit

/// Apple owns the complete web sign-in UI. iTM never injects JavaScript or reads form/cookie data.
struct OfficialAppleVerificationView: View {
    let onReturn: () -> Void
    @State private var host = "account.apple.com"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "lock.shield")
                Text(host).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("返回 iTM", action: onReturn)
            }
            .padding(16)
            Divider()
            Text("在 Apple 官方页面使用账号密码登录。收到设备验证码后，先返回 iTM 填写，不必在网页重复验证。")
                .font(.callout).foregroundStyle(.secondary)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            AppleVerificationWebView(host: $host)
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 640, idealHeight: 760)
    }
}

private struct AppleVerificationWebView: NSViewRepresentable {
    @Binding var host: String

    func makeCoordinator() -> Coordinator { Coordinator(host: $host) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: URL(string: "https://account.apple.com/")!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.stopLoading()
        nsView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private var host: Binding<String>
        init(host: Binding<String>) { self.host = host }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url,
                  url.scheme == "https", let hostname = url.host,
                  hostname == "apple.com" || hostname.hasSuffix(".apple.com") else {
                decisionHandler(.cancel)
                return
            }
            if navigationAction.targetFrame?.isMainFrame != false { host.wrappedValue = hostname }
            decisionHandler(.allow)
        }
    }
}
