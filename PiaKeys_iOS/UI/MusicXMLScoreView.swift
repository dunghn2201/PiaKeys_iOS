import SwiftUI
import WebKit

struct MusicXMLScoreView: UIViewRepresentable {
    let url: URL?
    let data: Data?
    let positionMilliseconds: Int64
    @Binding var contentHeight: CGFloat
    var heightRange: ClosedRange<CGFloat> = 120...420
    var showsAllPages = false

    init(
        url: URL,
        positionMilliseconds: Int64,
        contentHeight: Binding<CGFloat>,
        heightRange: ClosedRange<CGFloat> = 120...420,
        showsAllPages: Bool = false
    ) {
        self.url = url
        data = nil
        self.positionMilliseconds = positionMilliseconds
        _contentHeight = contentHeight
        self.heightRange = heightRange
        self.showsAllPages = showsAllPages
    }

    init(
        data: Data,
        positionMilliseconds: Int64,
        contentHeight: Binding<CGFloat>,
        heightRange: ClosedRange<CGFloat> = 120...420,
        showsAllPages: Bool = false
    ) {
        url = nil
        self.data = data
        self.positionMilliseconds = positionMilliseconds
        _contentHeight = contentHeight
        self.heightRange = heightRange
        self.showsAllPages = showsAllPages
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            contentHeight: $contentHeight,
            heightRange: heightRange,
            showsAllPages: showsAllPages
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "scoreHeight")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        context.coordinator.webView = webView
        context.coordinator.scoreURL = url
        context.coordinator.scoreData = data
        loadPage(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.contentHeight = $contentHeight
        context.coordinator.heightRange = heightRange
        if context.coordinator.scoreURL != url ||
            context.coordinator.scoreData != data ||
            context.coordinator.showsAllPages != showsAllPages {
            context.coordinator.scoreURL = url
            context.coordinator.scoreData = data
            context.coordinator.pageLoaded = false
            context.coordinator.renderedURL = nil
            context.coordinator.renderedData = nil
            context.coordinator.showsAllPages = showsAllPages
            loadPage(in: webView)
        } else if context.coordinator.pageLoaded {
            context.coordinator.renderScoreIfNeeded()
        }
        webView.evaluateJavaScript("window.setPlaybackTime(\(max(0, positionMilliseconds)));")
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "scoreHeight")
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

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var scoreURL: URL?
        var scoreData: Data?
        var renderedURL: URL?
        var renderedData: Data?
        var pageLoaded = false
        var contentHeight: Binding<CGFloat>
        var heightRange: ClosedRange<CGFloat>
        var showsAllPages: Bool

        init(
            contentHeight: Binding<CGFloat>,
            heightRange: ClosedRange<CGFloat>,
            showsAllPages: Bool
        ) {
            self.contentHeight = contentHeight
            self.heightRange = heightRange
            self.showsAllPages = showsAllPages
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageLoaded = true
            renderScoreIfNeeded()
        }

        func renderScoreIfNeeded() {
            guard pageLoaded,
                  let webView,
                  (renderedURL != scoreURL || renderedData != scoreData) else { return }
            let data: Data
            if let scoreData {
                data = scoreData
            } else if let scoreURL,
                      let fileData = try? Data(contentsOf: scoreURL) {
                data = fileData
            } else {
                return
            }
            renderedURL = scoreURL
            renderedData = scoreData
            let compressed = data.starts(with: [0x50, 0x4B])
            let base64 = data.base64EncodedString()
            let compressedArgument = compressed ? "true" : "false"
            let allPagesArgument = showsAllPages ? "true" : "false"
            webView.evaluateJavaScript(
                "window.renderScore('\(base64)', \(compressedArgument), \(allPagesArgument));"
            )
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "scoreHeight",
                  let height = message.body as? NSNumber else { return }
            let fittedHeight = CGFloat(truncating: height).clamped(to: heightRange)
            if abs(contentHeight.wrappedValue - fittedHeight) > 1 {
                contentHeight.wrappedValue = fittedHeight
            }
        }
    }
}
