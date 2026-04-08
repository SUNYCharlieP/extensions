import SwiftUI
import WebKit

struct ArticleReaderView: View {
    let item: FeedItem
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var bookmarkManager = BookmarkManager.shared
    @State private var isWebViewLoaded = false
    @State private var showSlowLoadHint = false

    var body: some View {
        VStack(spacing: 0) {
            // Custom header bar — avoids NavigationStack scroll-view
            // coordination that causes WKWebView bounce.
            readerToolbar

            ZStack {
                ReaderWebView(url: item.url, onFinished: {
                    withAnimation(.easeIn(duration: 0.3)) {
                        isWebViewLoaded = true
                    }
                    OfflineCacheManager.shared.cacheArticle(item)
                })
                .opacity(isWebViewLoaded ? 1 : 0)

                if !isWebViewLoaded {
                    readerLoadingState
                        .transition(.opacity)
                }
            }
        }
        .background(Color(.systemBackground))
    }

    private var readerToolbar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(item.source)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer()

            HStack(spacing: 16) {
                Button {
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    bookmarkManager.toggle(item)
                } label: {
                    Image(systemName: bookmarkManager.isBookmarked(item) ? "bookmark.fill" : "bookmark")
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var readerLoadingState: some View {
        VStack(spacing: 20) {
            // Article preview while loading
            if let imageURL = item.imageURL {
                CachedAsyncImage(url: imageURL)
                    .scaledToFill()
                    .frame(height: 200)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
        // Only block ad/tracking network domains — don't block anything else.
        // CSS hiding of page elements is handled separately via injected styles.
        let blockDomains = [
            "doubleclick\\\\.net", "googlesyndication\\\\.com",
            "googletagmanager\\\\.com", "google-analytics\\\\.com",
            "facebook\\\\.net", "amazon-adsystem\\\\.com",
            "adnxs\\\\.com", "taboola\\\\.com", "outbrain\\\\.com",
            "quantserve\\\\.com", "scorecardresearch\\\\.com",
            "chartbeat\\\\.com", "moatads\\\\.com", "criteo\\\\.com",
            "pubmatic\\\\.com", "rubiconproject\\\\.com",
            "adsafeprotected\\\\.com", "omtrdc\\\\.net",
            "adsrvr\\\\.org", "adservice\\\\.google",
            "pagead2\\\\.googlesyndication\\\\.com",
            "tpc\\\\.googlesyndication\\\\.com",
            "ad\\\\.doubleclick\\\\.net",
            "securepubads\\\\.g\\\\.doubleclick\\\\.net",
            "media\\\\.net", "smartadserver\\\\.com", "openx\\\\.net",
            "bidswitch\\\\.net", "sharethrough\\\\.com",
            "mathtag\\\\.com"
        ]
        var entries = blockDomains.map {
            "{\"trigger\":{\"url-filter\":\".*\($0)\"},\"action\":{\"type\":\"block\"}}"
        }
        // Minimal CSS-display-none for ad containers only — NOT page layout elements
        let cssHide = """
        {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":".ad, .ads, .advert, .advertisement, [class*=\\"adslot\\"], [class*=\\"ad-unit\\"], [class*=\\"ad-wrapper\\"], [class*=\\"ad-container\\"], [data-ad], [data-ad-slot], [data-advertisement], .cookie-banner, .consent-banner, .gdpr, #comments, .disqus, [class*=\\"taboola\\"], [class*=\\"outbrain\\"]"}}
        """
        entries.append(cssHide)
        let rules = "[" + entries.joined(separator: ",") + "]"

        WKContentRuleListStore.default().lookUpContentRuleList(forIdentifier: "ReaderRulesV6") { existing, _ in
            if let existing = existing {
                lock.lock()
                _compiled = existing
                lock.unlock()
                return
            }
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "ReaderRulesV6",
                encodedContentRuleList: rules
            ) { ruleList, _ in
                lock.lock()
                _compiled = ruleList
                lock.unlock()
            }
        }
    }
}

// MARK: - Reader Web View

struct ReaderWebView: UIViewRepresentable {
    let url: URL
    var onFinished: (() -> Void)?

    // Lightweight CSS injected at document START.
    // ONLY does: hide fixed/sticky chrome, basic typography, dark mode.
    // Does NOT hide broad class patterns that match content containers.
    private static let readerCSS = """
    (function() {
        var style = document.createElement('style');
        style.textContent = `
            /* Hide fixed/sticky overlays (nav bars, subscribe bars, cookie banners).
               Use attribute selectors on inline styles only — these are safe because
               real article content is never inline position:fixed. */
            [style*="position: fixed"], [style*="position:fixed"],
            [style*="position: sticky"], [style*="position:sticky"] {
                display: none !important;
            }

            /* Specific known site chrome — safe to hide */
            [role="banner"], [role="navigation"], [role="contentinfo"],
            .cookie-banner, .consent-banner, .gdpr-banner,
            [class*="paywall"], [class*="Paywall"],
            [class*="newsletter"], [class*="Newsletter"],
            [class*="subscribe-bar"], [class*="SubscribeBar"],
            [class*="cookie"], [class*="Cookie"],
            [class*="consent"], [class*="Consent"],
            #comments, .disqus {
                display: none !important;
            }

            /* ── Base typography ── */
            body {
                font-family: -apple-system, system-ui, sans-serif !important;
                font-size: 18px !important;
                line-height: 1.7 !important;
                max-width: 680px !important;
                margin: 0 auto !important;
                padding: 20px 16px 60px !important;
                -webkit-text-size-adjust: 100% !important;
                overflow-x: hidden !important;
            }

            /* ── Dark mode ── */
            @media (prefers-color-scheme: dark) {
                body {
                    color: #f0f0f0 !important;
                    background: #1c1c1e !important;
                }
                a { color: #FF854F !important; }
                h1, h2, h3, h4, h5, h6 { color: #ffffff !important; }
                img { opacity: 0.92; }
                pre, code {
                    background: #2c2c2e !important;
                    color: #e5e5e5 !important;
                }
            }

            /* ── Light mode ── */
            @media (prefers-color-scheme: light) {
                body {
                    color: #1a1a1a !important;
                    background: #ffffff !important;
                }
                a { color: #FF7A3D !important; }
            }

            /* ── Images ── */
            img {
                max-width: 100% !important;
                height: auto !important;
            }

            /* ── Headings ── */
            h1, h2, h3 {
                font-weight: 700 !important;
                line-height: 1.3 !important;
            }
            h1 { font-size: 26px !important; }
            h2 { font-size: 21px !important; }

            figure {
                margin: 16px 0 !important;
                padding: 0 !important;
            }
            figcaption {
                font-size: 14px !important;
                color: #8e8e93 !important;
                margin-top: 6px !important;
            }
            blockquote {
                border-left: 3px solid #FF7A3D !important;
                padding-left: 16px !important;
                margin: 16px 0 !important;
                font-style: italic !important;
            }
            iframe, video {
                max-width: 100% !important;
            }

            /* Remove outlines/focus rings that show as blue lines */
            *:focus { outline: none !important; }
        `;
        document.documentElement.appendChild(style);
    })();
    """

    // Post-load JS: hide fixed/sticky elements that JS inserts after page load
    private static let postLoadCleanup = """
    (function() {
        function killFixed(el) {
            if (!el || !el.getBoundingClientRect) return;
            var s = window.getComputedStyle(el);
            if (s.position === 'fixed' || s.position === 'sticky') {
                var rect = el.getBoundingClientRect();
                // Only kill elements that look like nav bars / banners
                // (short height, pinned to top or bottom edge)
                if (rect.height < 200 || rect.top < 10 || rect.bottom > window.innerHeight - 10) {
                    el.style.setProperty('display', 'none', 'important');
                }
            }
        }
        function scanTopLevel() {
            if (!document.body) return;
            var kids = document.body.children;
            for (var i = 0; i < kids.length; i++) {
                killFixed(kids[i]);
            }
        }
        scanTopLevel();
        setTimeout(scanTopLevel, 2000);
        setTimeout(scanTopLevel, 5000);
        // Watch for dynamically-inserted fixed elements on body only
        if (window.MutationObserver && document.body) {
            var obs = new MutationObserver(function(mutations) {
                for (var m = 0; m < mutations.length; m++) {
                    var added = mutations[m].addedNodes;
                    for (var n = 0; n < added.length; n++) {
                        if (added[n].nodeType === 1) killFixed(added[n]);
                    }
                }
            });
            obs.observe(document.body, { childList: true, subtree: false });
        }
    })();
    """

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        if let rules = ReaderContentRules.compiled {
            config.userContentController.add(rules)
        }

        let cssScript = WKUserScript(
            source: Self.readerCSS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(cssScript)

        let cleanupJS = WKUserScript(
            source: Self.postLoadCleanup,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(cleanupJS)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = false
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .never
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
            // Timeout fallback — force-show after 8 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                self?.complete()
            }
        }

        private func complete() {
            guard !hasFinished else { return }
            hasFinished = true
            onFinished?()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
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

        // Allow redirects — some sites (Ars Technica) redirect before serving content
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
    }
}
