import SwiftUI
import WebKit

struct MusicXMLScoreView: UIViewRepresentable {
    private static let playbackHighlightIntervalMilliseconds: Int64 = 100

    let url: URL?
    let data: Data?
    let positionMilliseconds: Int64
    @Binding var contentHeight: CGFloat
    var heightRange: ClosedRange<CGFloat> = 120...420
    var showsAllPages = false
    var page = 1
    var onPageCount: ((Int) -> Void)?
    var onPageChange: ((Int) -> Void)?

    init(
        url: URL,
        positionMilliseconds: Int64,
        contentHeight: Binding<CGFloat>,
        heightRange: ClosedRange<CGFloat> = 120...420,
        showsAllPages: Bool = false,
        page: Int = 1,
        onPageCount: ((Int) -> Void)? = nil,
        onPageChange: ((Int) -> Void)? = nil
    ) {
        self.url = url
        data = nil
        self.positionMilliseconds = positionMilliseconds
        _contentHeight = contentHeight
        self.heightRange = heightRange
        self.showsAllPages = showsAllPages
        self.page = max(1, page)
        self.onPageCount = onPageCount
        self.onPageChange = onPageChange
    }

    init(
        data: Data,
        positionMilliseconds: Int64,
        contentHeight: Binding<CGFloat>,
        heightRange: ClosedRange<CGFloat> = 120...420,
        showsAllPages: Bool = false,
        page: Int = 1,
        onPageCount: ((Int) -> Void)? = nil,
        onPageChange: ((Int) -> Void)? = nil
    ) {
        url = nil
        self.data = data
        self.positionMilliseconds = positionMilliseconds
        _contentHeight = contentHeight
        self.heightRange = heightRange
        self.showsAllPages = showsAllPages
        self.page = max(1, page)
        self.onPageCount = onPageCount
        self.onPageChange = onPageChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            contentHeight: $contentHeight,
            heightRange: heightRange,
            showsAllPages: showsAllPages,
            page: page,
            onPageCount: onPageCount,
            onPageChange: onPageChange
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "scoreHeight")
        configuration.userContentController.add(context.coordinator, name: "scoreStatus")
        configuration.userContentController.add(context.coordinator, name: "scorePage")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        // The score document is always rendered on a white page. Keeping the
        // WebView opaque avoids an extra transparent compositing pass while a
        // score card moves inside a ScrollView.
        webView.isOpaque = true
        webView.backgroundColor = .white
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.alwaysBounceVertical = false
        context.coordinator.webView = webView
        context.coordinator.scoreURL = url
        context.coordinator.scoreData = data
        loadPage(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.contentHeight = $contentHeight
        context.coordinator.heightRange = heightRange
        context.coordinator.onPageCount = onPageCount
        context.coordinator.onPageChange = onPageChange
        if context.coordinator.scoreURL != url ||
            context.coordinator.scoreData != data ||
            context.coordinator.showsAllPages != showsAllPages {
            context.coordinator.scoreURL = url
            context.coordinator.scoreData = data
            context.coordinator.page = max(1, page)
            context.coordinator.renderedPage = 0
            context.coordinator.pageLoaded = false
            context.coordinator.renderedURL = nil
            context.coordinator.renderedData = nil
            context.coordinator.renderRequestID += 1
            context.coordinator.pendingRenderRequestID = nil
            context.coordinator.sentPlaybackTimeMilliseconds = nil
            context.coordinator.isPreparingRender = false
            context.coordinator.showsAllPages = showsAllPages
            loadPage(in: webView)
        } else if context.coordinator.pageLoaded {
            context.coordinator.renderScoreIfNeeded()
            context.coordinator.updatePage(page)
        }
        context.coordinator.updatePlaybackTime(positionMilliseconds)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "scoreHeight")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "scoreStatus")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "scorePage")
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
        var renderRequestID = 0
        var pendingRenderRequestID: Int?
        var pageLoaded = false
        var isPreparingRender = false
        var pendingPlaybackTimeMilliseconds: Int64 = 0
        var sentPlaybackTimeMilliseconds: Int64?
        var contentHeight: Binding<CGFloat>
        var heightRange: ClosedRange<CGFloat>
        var showsAllPages: Bool
        var page: Int
        var renderedPage = 0
        var onPageCount: ((Int) -> Void)?
        var onPageChange: ((Int) -> Void)?

        init(
            contentHeight: Binding<CGFloat>,
            heightRange: ClosedRange<CGFloat>,
            showsAllPages: Bool,
            page: Int,
            onPageCount: ((Int) -> Void)?,
            onPageChange: ((Int) -> Void)?
        ) {
            self.contentHeight = contentHeight
            self.heightRange = heightRange
            self.showsAllPages = showsAllPages
            self.page = max(1, page)
            self.onPageCount = onPageCount
            self.onPageChange = onPageChange
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageLoaded = true
            renderScoreIfNeeded()
        }

        func updatePlaybackTime(_ milliseconds: Int64) {
            let value = max(0, milliseconds)
            pendingPlaybackTimeMilliseconds = value
            guard pageLoaded,
                  let webView,
                  sentPlaybackTimeMilliseconds == nil ||
                    abs(value - (sentPlaybackTimeMilliseconds ?? value)) >= MusicXMLScoreView.playbackHighlightIntervalMilliseconds else { return }
            sentPlaybackTimeMilliseconds = value
            webView.evaluateJavaScript("window.setPlaybackTime(\(value));")
        }

        func updatePage(_ requestedPage: Int) {
            let nextPage = max(1, requestedPage)
            guard page != nextPage || renderedPage != nextPage else { return }
            page = nextPage
            guard pageLoaded, let webView else { return }
            renderedPage = nextPage
            webView.evaluateJavaScript("window.setScorePage(\(nextPage));")
        }

        func renderScoreIfNeeded() {
            guard pageLoaded,
                  let webView,
                  !isPreparingRender,
                  pendingRenderRequestID == nil,
                  (renderedURL != scoreURL || renderedData != scoreData) else { return }
            renderRequestID += 1
            let requestID = renderRequestID
            pendingRenderRequestID = requestID
            isPreparingRender = true
            let sourceData = scoreData
            let sourceURL = scoreURL
            let renderAllPages = showsAllPages
            let requestedPage = page
            DispatchQueue.global(qos: .userInitiated).async { [weak self, weak webView] in
                let data: Data?
                if let sourceData {
                    data = sourceData
                } else if let sourceURL {
                    data = try? Data(contentsOf: sourceURL)
                } else {
                    data = nil
                }
                let base64 = data?.base64EncodedString()
                let compressed = data?.starts(with: [0x50, 0x4B]) == true
                DispatchQueue.main.async {
                    guard let self, self.renderRequestID == requestID else { return }
                    self.isPreparingRender = false
                    guard self.pageLoaded, let webView, let base64 else {
                        self.pendingRenderRequestID = nil
                        return
                    }
                    self.renderedPage = requestedPage
                    let compressedArgument = compressed ? "true" : "false"
                    let allPagesArgument = renderAllPages ? "true" : "false"
                    webView.evaluateJavaScript(
                        "window.renderScore('\(base64)', \(compressedArgument), \(allPagesArgument), \(requestID), \(requestedPage));"
                    ) { [weak self] _, error in
                        guard let self, error != nil,
                              self.pendingRenderRequestID == requestID else { return }
                        self.pendingRenderRequestID = nil
                    }
                    if self.page != requestedPage {
                        self.renderedPage = self.page
                        webView.evaluateJavaScript("window.setScorePage(\(self.page));")
                    }
                }
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "scoreHeight", let height = message.body as? NSNumber {
                let fittedHeight = CGFloat(truncating: height).clamped(to: heightRange)
                if abs(contentHeight.wrappedValue - fittedHeight) > 1 {
                    contentHeight.wrappedValue = fittedHeight
                }
                return
            }
            if message.name == "scorePage", let value = message.body as? NSNumber {
                let nextPage = max(1, value.intValue)
                page = nextPage
                renderedPage = nextPage
                onPageChange?(nextPage)
                return
            }
            guard message.name == "scoreStatus",
                  let payload = message.body as? [String: Any],
                  let token = payload["token"] as? Int,
                  let success = payload["success"] as? Bool,
                  token == pendingRenderRequestID else { return }
            pendingRenderRequestID = nil
            if let pageCount = (payload["pageCount"] as? NSNumber)?.intValue {
                onPageCount?(pageCount)
            }
            if success {
                renderedURL = scoreURL
                renderedData = scoreData
                sentPlaybackTimeMilliseconds = nil
                updatePlaybackTime(pendingPlaybackTimeMilliseconds)
            }
        }
    }
}
