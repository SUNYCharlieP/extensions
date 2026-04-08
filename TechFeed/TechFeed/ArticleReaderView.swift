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
        let rules: String = {
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
                "contextual\\\\.media\\\\.net",
                "media\\\\.net", "yimg\\\\.com/cy",
                "infosys\\\\.com", "topaz\\\\.com",
                "smartadserver\\\\.com", "openx\\\\.net",
                "indexexchange\\\\.com", "casalemedia\\\\.com",
                "bidswitch\\\\.net", "sharethrough\\\\.com",
                "spotxchange\\\\.com", "mathtag\\\\.com"
            ]
            var entries = blockDomains.map {
                "{\"trigger\":{\"url-filter\":\".*\($0)\"},\"action\":{\"type\":\"block\"}}"
            }
            let cssHide = "{\"trigger\":{\"url-filter\":\".*\"},\"action\":{\"type\":\"css-display-none\",\"selector\":\".ad, .ads, .advert, .advertisement, [class*=\\\"ad-\\\"], [class*=\\\"adslot\\\"], [class*=\\\"ad_\\\"], [class*=\\\"adBox\\\"], [class*=\\\"ad-unit\\\"], [id*=\\\"ad-\\\"], [id*=\\\"ad_\\\"], iframe[src*=\\\"ad\\\"], .cookie-banner, .consent-banner, .gdpr, #comments, .disqus, .paywall, .gate, [class*=\\\"promo\\\"], [class*=\\\"sponsor\\\"], [class*=\\\"taboola\\\"], [class*=\\\"outbrain\\\"], [data-ad], [data-advertisement], [data-ad-slot], [class*=\\\"ad-placement\\\"], [class*=\\\"sponsored\\\"], [class*=\\\"Sponsored\\\"], [class*=\\\"partner\\\"], [class*=\\\"Partner\\\"], [class*=\\\"insights\\\"], [aria-label*=\\\"advertisement\\\"], [aria-label*=\\\"Advertisement\\\"]\"}}"
            entries.append(cssHide)
            return "[" + entries.joined(separator: ",") + "]"
        }()
        // Try cached rules first (instant), then compile as fallback — bump identifier when changing rules
        WKContentRuleListStore.default().lookUpContentRuleList(forIdentifier: "ReaderRulesV5") { existing, _ in
            if let existing = existing {
                lock.lock()
                _compiled = existing
                lock.unlock()
                return
            }
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "ReaderRulesV5",
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

    // Injected at document START — styles are in place before the page renders,
    // so there is zero reflow when site content loads.
    private static let readerCSS = """
    (function() {
        var style = document.createElement('style');
        style.textContent = `
            /* ── Hide site chrome ── */
            /* Top-level structural elements */
            body > nav, body > header, body > footer, body > aside,
            body > div > nav, body > div > header, body > div > footer,
            [role="navigation"], [role="banner"], [role="contentinfo"],

            /* CRITICAL: Hide ALL fixed/sticky positioned elements — these are
               the nav bars, subscribe bars, and ad banners that overlap content */
            [style*="position: fixed"], [style*="position:fixed"],
            [style*="position: sticky"], [style*="position:sticky"],

            /* Specific class patterns for site UI */
            [class*="site-nav"], [class*="site-header"], [class*="site-footer"],
            [class*="global-nav"], [class*="global-header"], [class*="main-nav"],
            [class*="top-bar"], [class*="topbar"], [class*="masthead"],
            [class*="sidebar"], [class*="Sidebar"],
            [class*="trending"], [class*="Trending"],
            [class*="related-articles"], [class*="RelatedArticles"],
            [class*="signup"], [class*="SignUp"],
            [class*="signin"], [class*="SignIn"],
            [class*="subscribe"], [class*="Subscribe"],
            [class*="banner"], [class*="Banner"],
            [class*="toast"], [class*="Toast"],
            [class*="drawer"], [class*="Drawer"],
            [class*="modal"], [class*="Modal"],
            [class*="overlay"], [class*="Overlay"],
            [class*="popup"], [class*="Popup"],
            [class*="cookie"], [class*="Cookie"],
            [class*="consent"], [class*="Consent"],
            [class*="newsletter"], [class*="Newsletter"],
            [class*="social-share"], [class*="SocialShare"],
            [class*="hamburger"], [class*="menu-toggle"],
            [class*="paywall"], [class*="Paywall"],
            [class*="promo-bar"], [class*="PromoBar"],
            [class*="ad-wrapper"], [class*="adWrapper"],
            [class*="ad-container"], [class*="adContainer"],
            [class*="advertisement"], [class*="Advertisement"],
            [class*="leaderboard"], [class*="Leaderboard"],
            [class*="sticky-nav"], [class*="stickyNav"],
            [class*="sticky-header"], [class*="stickyHeader"],
            [class*="fixed-nav"], [class*="fixedNav"],
            [class*="fixed-header"], [class*="fixedHeader"],
            [id*="site-nav"], [id*="site-header"], [id*="site-footer"],
            [id*="sidebar"], [id*="cookie"], [id*="consent"],
            [id*="banner"], [id*="popup"],
            [id*="ad-"], [id*="leaderboard"],
            [data-ad], [data-advertisement], [data-ad-slot] {
                display: none !important;
            }

            /* Force site chrome elements to static — prevents nav bars,
               subscribe bars, and ad banners from overlapping article content.
               Only target elements likely to be fixed/sticky chrome, not article layout. */
            body > header, body > nav, body > footer, body > aside,
            body > div > header, body > div > nav, body > div > footer,
            [role="navigation"], [role="banner"], [role="contentinfo"] {
                position: static !important;
            }

            /* ── Base typography ── */
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
                overflow-x: hidden !important;
            }

            /* ── Dark mode ── */
            @media (prefers-color-scheme: dark) {
                body {
                    color: #f0f0f0 !important;
                    background: #1c1c1e !important;
                }
                * {
                    color: inherit !important;
                    border-color: #3a3a3c !important;
                }
                body div, body section, body article, body main,
                body span, body p, body li, body td, body th,
                body figure, body figcaption, body blockquote,
                body header, body footer, body aside, body nav,
                body form, body label, body ul, body ol {
                    background-color: transparent !important;
                    background-image: none !important;
                }
                a { color: #FF854F !important; }
                h1, h2, h3, h4, h5, h6 { color: #ffffff !important; }
                img { opacity: 0.92; }
                pre, code, .highlight {
                    background: #2c2c2e !important;
                    color: #e5e5e5 !important;
                }
                figcaption, .caption { color: #8e8e93 !important; }
                blockquote { color: #adadb1 !important; }
                table, th, td { border-color: #3a3a3c !important; }
                input, textarea, select, button {
                    background: #2c2c2e !important;
                    color: #f0f0f0 !important;
                }
            }

            /* ── Images ── */
            img {
                max-width: 100% !important;
                height: auto !important;
                border-radius: 8px !important;
                margin: 12px 0 !important;
                display: block !important;
                position: static !important;
                float: none !important;
            }

            /* ── Headings ── */
            h1, h2, h3 {
                font-weight: 700 !important;
                line-height: 1.3 !important;
                margin-top: 24px !important;
            }
            h1 { font-size: 26px !important; }
            h2 { font-size: 21px !important; }
            p { margin: 14px 0 !important; }
            a { color: #FF7A3D !important; }

            /* ── Figures ── */
            figure {
                margin: 16px 0 !important;
                padding: 0 !important;
                position: static !important;
                overflow: hidden !important;
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
                color: #6e6e73 !important;
                font-style: italic !important;
            }
            iframe, video {
                max-width: 100% !important;
                position: static !important;
            }
            table { font-size: 15px !important; }

            /* ── Code blocks ── */
            pre, code, .highlight {
                background: #f5f5f5 !important;
                overflow-x: auto !important;
            }
        `;
        document.documentElement.appendChild(style);
    })();
    """

    // Injected at document END — catches fixed/sticky elements that sites
    // inject via JavaScript after the initial HTML loads.
    private static let postLoadCleanup = """
    (function() {
        function killFixed(el) {
            var s = window.getComputedStyle(el);
            if (s.position === 'fixed' || s.position === 'sticky') {
                var rect = el.getBoundingClientRect();
                // Kill nav bars / banners: short overlays or pinned to top/bottom edges
                if (rect.height < 200 || rect.top < 10 || rect.bottom > window.innerHeight - 10) {
                    el.style.display = 'none';
                }
            }
        }
        // Targeted scan: only check direct children of body and their children
        // (where fixed nav/subscribe bars live), NOT the entire DOM.
        function scanTopLevel() {
            var kids = document.body ? document.body.children : [];
            for (var i = 0; i < kids.length; i++) {
                killFixed(kids[i]);
                var grandkids = kids[i].children;
                for (var j = 0; j < grandkids.length; j++) {
                    killFixed(grandkids[j]);
                }
            }
        }
        scanTopLevel();
        setTimeout(scanTopLevel, 1500);
        // Watch for dynamically-inserted fixed elements
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
            // Also observe first-level divs (common wrapper pattern)
            var topDivs = document.body.querySelectorAll(':scope > div');
            for (var d = 0; d < topDivs.length; d++) {
                obs.observe(topDivs[d], { childList: true, subtree: false });
            }
        }
    })();
    """

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        if let rules = ReaderContentRules.compiled {
            config.userContentController.add(rules)
        }

        // Inject CSS at document START — before any site content renders.
        // This is the single most important anti-bounce measure: the browser
        // only lays out once with our styles already in place, so there is
        // no reflow flash or content-size oscillation.
        let cssScript = WKUserScript(
            source: Self.readerCSS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(cssScript)

        // Post-load cleanup: kill fixed/sticky elements injected by JS after page load
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
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.alwaysBounceHorizontal = false
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
            // CSS was injected at document start so layout is already settled.
            // Short delay lets any late-loading site JS finish before reveal.
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
            // Don't show yet — wait for didFinish so layout has settled
            // and our reader CSS has been applied, preventing visible reflow.
        }
    }
}
