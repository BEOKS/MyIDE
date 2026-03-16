import AppKit
import SwiftUI
import WebKit
import MyIDECore

struct BrowserWebView: NSViewRepresentable {
    let urlString: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        load(urlString, into: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let target = normalized(urlString)
        guard nsView.url?.absoluteString != target else { return }
        load(target, into: nsView)
    }

    private func load(_ value: String, into webView: WKWebView) {
        guard let url = URL(string: normalized(value)) else { return }
        webView.load(URLRequest(url: url))
    }

    private func normalized(_ value: String) -> String {
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return value
        }

        return "https://\(value)"
    }
}

struct MarkdownPreviewContent: View {
    let filePath: String

    var body: some View {
        Group {
            if filePath.isEmpty {
                Text("Choose a markdown file.")
                    .foregroundStyle(.secondary)
            } else if let html = try? MarkdownPreviewRenderer.html(forMarkdownFileAt: filePath) {
                MarkdownWebView(html: html)
            } else {
                Text("Unable to load markdown file.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ImagePreviewContent: View {
    let filePath: String

    var body: some View {
        Group {
            if filePath.isEmpty {
                Text("Choose an image file.")
                    .foregroundStyle(.secondary)
            } else if let image = NSImage(contentsOfFile: filePath) {
                GeometryReader { geometry in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            } else {
                Text("Unable to load image file.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.loadHTMLString(html, baseURL: nil)
    }
}
