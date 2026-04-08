import SwiftUI
import WebKit

struct ArticleReaderView: View {
    let item: FeedItem
    @Environment(\.dismiss) private var dismiss
    @State private var isWebViewLoaded = false
    @State private var showSlowLoadHint = false

    var body: some View {
        NavigationStack {
            ZStack {
                ReaderWebView(url: item.url, onFinished: {
                    withAnimation(.easeIn(duration: 0.3)) {
                        isWebViewLoaded = true
                    }
                    // Cache for offline after reading
                    OfflineCacheManager.shared.cacheArticle(item)
                })
                .ignoresSafeArea(edges: .bottom)
                .opacity(isWebViewLoaded ? 1 : 0)

                if !isWebViewLoaded {
                    readerLoadingState
                        .transition(.opacity)
                }
            }
            .navigationTitle(item.source)
            .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 16) {
                            Button {
                                let impact = UIImpactFeedbackGenerator(style: .medium)
                                impact.impactOccurred()
                                BookmarkManager.shared.toggle(item)
                            } label: {
                                Image(systemName: BookmarkManager.shared.isBookmarked(item) ? "bookmark.fill" : "bookmark")
                                    .foregroundColor(.arcaOrange)
                            }

                            ShareLink(item: item.url) {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundColor(.arcaOrange)
                            }
                            Link(destination: item.url) {
                                Image(systemName: "safari")
                                    .foregroundColor(.arcaOrange)
                            }
                        }
                    }
                }
        }
    }

    private var readerLoadingState: some View {
        VStack(spacing: 20) {
            // Article preview while loading
            if let imageURL = item.imageURL {
                AsyncImage(url: imageURL) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 200)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .frame(height: 200)
                .padding(.horizontal)
            }

            VStack(spacing: 12) {
                Text(item.title)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                HStack(spacing: 6) {
                    Text(item.source)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.arcaOrange)
                }
            }

            ArcaLoadingView()
                .scaleEffect(0.7)
                .padding(.top, 8)

            if showSlowLoadHint {
                VStack(spacing: 10) {
                    Text("Taking longer than usual...")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Link(destination: item.url) {
                        HStack(spacing: 4) {
                            Image(systemName: "safari")
                            Text("Open in Safari")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.arcaOrange)
                    }
                }
                .transition(.opacity)
            }

            Spacer()
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                if !isWebViewLoaded {
                    withAnimation { showSlowLoadHint = true }
                }
            }
        }
    }
}

// MARK: - Precompiled Content Rules

enum ReaderContentRules {
    private static let lock = NSLock()
    private static var _compiled: WKContentRuleList?
    static var compiled: WKContentRuleList? {
        lock.lock()
        defer { lock.unlock() }
        return _compiled
    }

    static func precompile() {
        let rules = """
        [{"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":"header, footer, nav, .nav, .navbar, .menu, .sidebar, .ad, .ads, .advert, .advertisement, .banner, .cookie, .cookie-banner, .consent, .gdpr, .popup, .modal, .overlay, .newsletter, .subscribe, .subscription, .signup, .sign-up, .social-share, .share-buttons, .related, .recommended, .comments, .comment-section, #comments, .disqus, [class*=cookie], [class*=consent], [class*=banner], [class*=popup], [class*=newsletter], [class*=subscribe], [id*=cookie], [id*=consent], [id*=banner], [id*=popup], [id*=newsletter], [id*=subscribe], .site-header, .site-footer, .global-header, .global-footer, .masthead, .top-bar, .bottom-bar, .sticky-bar, .paywall, .gate, .promo, .promotion, [role=banner], [role=navigation], [role=complementary], [role=contentinfo], aside"}}]
        """
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "ReaderRules",
            encodedContentRuleList: rules
        ) { ruleList, _ in
            lock.lock()
            _compiled = ruleList
            lock.unlock()
        }
    }
}

// MARK: - Reader Web View

struct ReaderWebView: UIViewRepresentable {
    let url: URL
    var onFinished: (() -> Void)?

    private static let readerJS = """
    (function() {
        var style = document.createElement('style');
        style.textContent = `
            body {
                font-family: -apple-system, system-ui, sans-serif !important;
                font-size: 18px !important;
                line-height: 1.7 !important;
                color: #1a1a1a !important;
                background: #ffffff !important;
                max-width: 680px !important;
                margin: 0 auto !important;
                padding: 20px 16px 60px !important;
                -webkit-text-size-adjust: 100% !important;
            }
            /* Force all inner elements to inherit reader colors */
            body *, body *::before, body *::after {
                background-color: transparent !important;
                border-color: #e5e5ea !important;
            }
            /* Restore specific backgrounds that should keep color */
            pre, code, .highlight {
                background: #f5f5f5 !important;
            }
            @media (prefers-color-scheme: dark) {
                body {
                    color: #e5e5e5 !important;
                    background: #1c1c1e !important;
                }
                body *, body *::before, body *::after {
                    color: inherit !important;
                    border-color: #38383a !important;
                }
                /* Let links and specific elements keep their colors */
                a { color: #FF854F !important; }
                img { opacity: 0.9; }
                pre, code, .highlight {
                    background: #2c2c2e !important;
                    color: #e5e5e5 !important;
                }
                figcaption { color: #8e8e93 !important; }
                blockquote { color: #98989d !important; }
                table, th, td {
                    background-color: transparent !important;
                    color: #e5e5e5 !important;
                }
            }
            img {
                max-width: 100% !important;
                height: auto !important;
                border-radius: 12px !important;
                margin: 16px 0 !important;
                background-color: transparent !important;
            }
            h1, h2, h3 {
                font-weight: 700 !important;
                line-height: 1.3 !important;
                margin-top: 24px !important;
            }
            h1 { font-size: 28px !important; }
            h2 { font-size: 22px !important; }
            p { margin: 14px 0 !important; }
            a { color: #FF7A3D !important; }
            figure { margin: 16px 0 !important; padding: 0 !important; }
            figcaption {
                font-size: 14px !important;
                color: #8e8e93 !important;
                margin-top: 8px !important;
            }
            blockquote {
                border-left: 3px solid #FF7A3D !important;
                padding-left: 16px !important;
                margin: 16px 0 !important;
                color: #6e6e73 !important;
                font-style: italic !important;
            }
            iframe, video { max-width: 100% !important; }
            table { font-size: 15px !important; }
            [style*="position: fixed"], [style*="position:fixed"],
            [style*="position: sticky"], [style*="position:sticky"] {
                display: none !important;
            }
        `;
        document.head.appendChild(style);
    })();
    """

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        if let rules = ReaderContentRules.compiled {
            config.userContentController.add(rules)
        }

        let userScript = WKUserScript(
            source: Self.readerJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(userScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .always
        webView.navigationDelegate = context.coordinator

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        webView.load(request)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinished: onFinished)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let onFinished: (() -> Void)?
        private var hasFinished = false

        init(onFinished: (() -> Void)?) {
            self.onFinished = onFinished
            super.init()
            // Timeout fallback — force-show after 6 seconds even if didFinish never fires
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                self?.complete()
            }
        }

        private func complete() {
            guard !hasFinished else { return }
            hasFinished = true
            onFinished?()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.complete()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { [weak self] in
                self?.complete()
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { [weak self] in
                self?.complete()
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            // Show content once first bytes render — faster than waiting for full didFinish
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.complete()
            }
        }
    }
}
