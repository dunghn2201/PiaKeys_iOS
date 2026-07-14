import SwiftUI
import WebKit

struct MusicXMLScoreView: UIViewRepresentable {
    let url: URL
    let positionMilliseconds: Int64

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        context.coordinator.webView = webView
        context.coordinator.scoreURL = url
        loadPage(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.scoreURL != url {
            context.coordinator.scoreURL = url
            context.coordinator.pageLoaded = false
            loadPage(in: webView)
        } else if context.coordinator.pageLoaded {
            context.coordinator.renderScoreIfNeeded()
        }
        webView.evaluateJavaScript("window.setPlaybackTime(\(max(0, positionMilliseconds)));")
    }

    private func loadPage(in webView: WKWebView) {
        let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Score")
            ?? Bundle.main.url(forResource: "index", withExtension: "html")
        guard let indexURL else {
            webView.loadHTMLString("<p style='font: -apple-system-body; color: #777'>Score renderer is unavailable.</p>", baseURL: nil)
            return
        }
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var scoreURL: URL?
        var renderedURL: URL?
        var pageLoaded = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageLoaded = true
            renderScoreIfNeeded()
        }

        func renderScoreIfNeeded() {
            guard pageLoaded,
                  let webView,
                  let scoreURL,
                  renderedURL != scoreURL,
                  let data = try? Data(contentsOf: scoreURL) else { return }
            renderedURL = scoreURL
            let compressed = data.starts(with: [0x50, 0x4B])
            let base64 = data.base64EncodedString()
            webView.evaluateJavaScript("window.renderScore('\(base64)', \(compressed ? "true" : "false"));")
        }
    }
}
