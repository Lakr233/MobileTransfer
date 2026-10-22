//
//  WebView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    let url: URL?
    let frame: CGRect = .init(origin: .zero, size: .init(width: 666, height: 444))

    func makeNSView(context _: Context) -> some NSView {
        let view = WKWebView(frame: .zero)
        if let url { view.load(URLRequest(url: url)) }
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: frame.width).isActive = true
        view.heightAnchor.constraint(equalToConstant: frame.height).isActive = true
        return view
    }

    func updateNSView(_: NSViewType, context _: Context) {}
}

struct WebSheetView: View {
    let url: URL?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            WebView(url: url)
            Divider()
            HStack {
                Text(url?.absoluteString ?? "")
                    .textSelection(.enabled)
                Spacer()
                Button("Close") { dismiss() }
                    .foregroundStyle(.tint)
            }
            .padding(16)
        }
    }
}
