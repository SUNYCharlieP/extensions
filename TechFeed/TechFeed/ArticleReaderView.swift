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
        {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":".ad, .ads, .advert, .advertisement, [class*=\\"adslot\\"], [class*=\\"ad-unit\\"], [class*=\\"ad-wrapper\\"], [class*=\\"ad-container\\"], [data-ad], [data-ad-slot], [data-advertisement], .cookie-banner, .consent-banner, .gdpr, #comments, .disqus, [class*=\\"taboola\\"], [class*=\\"outbrain\\"], [class*=\\"onetrust\\"], [class*=\\"OneTrust\\"], #onetrust-consent-sdk, [class*=\\"evidon\\"], [class*=\\"truste\\"], [id*=\\"consent\\"], [class*=\\"consent-modal\\"], [class*=\\"cookie-notice\\"], [class*=\\"cookie-wall\\"], [class*=\\"c-globalModal\\"], [class*=\\"newsletter-modal\\"], [class*=\\"signup-modal\\"], [class*=\\"overlay-modal\\"]"}}
        """
        entries.append(cssHide)
        let rules = "[" + entries.joined(separator: ",") + "]"

        WKContentRuleListStore.default().lookUpContentRuleList(forIdentifier: "ReaderRulesV9") { existing, _ in
            if let existing = existing {
                lock.lock()
                _compiled = existing
                lock.unlock()
                return
            }
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "ReaderRulesV9",
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

    // ── Minimal CSS ──
    // NO element hiding. NO layout overrides. NO JS cleanup.
    // Ad blocking is handled entirely by WKContentRuleList (network-level).
    // We only inject: overflow-x fix, dark/light mode colors, image scaling,
    // and focus-outline removal. Nothing that can break page content.
    private static let readerCSS = """
    (function() {
        var style = document.createElement('style');
        style.textContent = `
            body {
                -webkit-text-size-adjust: 100% !important;
                overflow-x: hidden !important;
            }
            img { max-width: 100% !important; height: auto !important; }
            iframe, video { max-width: 100% !important; }
            *:focus { outline: none !important; }

            @media (prefers-color-scheme: dark) {
                body { color: #f0f0f0 !important; background: #1c1c1e !important; }
                a { color: #FF854F !important; }
                h1,h2,h3,h4,h5,h6 { color: #fff !important; }
                img { opacity: 0.92; }
                pre, code { background: #2c2c2e !important; color: #e5e5e5 !important; }
            }
            @media (prefers-color-scheme: light) {
                body { color: #1a1a1a !important; background: #fff !important; }
                a { color: #FF7A3D !important; }
            }

            /* Hide broken oEmbed/API error JSON blocks */
            .fb-post, .instagram-media,
            [data-instgrm-captioned],
            [class*="embed-error"], [class*="oembed-error"] {
                display: none !important;
            }

            /* Kill paywall overlays — precise selectors only.
               Avoid broad substring matches like "gate" (matches navigate),
               "gradient" (matches decorative CSS), "truncat" (matches UI truncation). */
            [class*="paywall"], [class*="Paywall"],
            [class*="metering"], [class*="Metering"],
            [class*="regwall"], [class*="Regwall"],
            [class*="subscribe-wall"], [class*="SubscribeWall"],
            [class*="piano-"], [id*="paywall"],
            [id*="piano"], [class*="tp-modal"],
            [class*="tp-backdrop"], .tp-active,
            [data-piano-id],
            .overlay-no-scroll, .noscroll,
            [class*="PigeonPaywall"],
            [class*="duet--article--article-body-component"] ~ div[class*="z-"],
            /* Vox Media / The Verge paywall */
            [class*="duet--cta"],
            [class*="paywall-overlay"],
            [class*="subscriber-only"],
            [class*="c-entry-content__paywall"],
            [class*="c-floating-button"],
            [class*="c-chorus-card"],
            [class*="hub-peek-embed"],
            [class*="enthusiast-ad"],
            /* Wired / Conde Nast paywall */
            [class*="paywall-bar"],
            [class*="journey-unit"],
            [class*="RecircMostPopularContainer"],
            [data-testid*="paywall"],
            [data-testid*="GenericCallout"] {
                display: none !important;
            }
        `;
        if (document.documentElement) {
            document.documentElement.appendChild(style);
        } else {
            document.addEventListener('DOMContentLoaded', function() {
                document.documentElement.appendChild(style);
            });
        }
    })();
    """

    private static let postLoadPaywallKill = """
    (function() {
        function killPaywall() {
            if (!document.body) return;
            // Remove overflow:hidden from body/html that paywalls add
            document.documentElement.style.setProperty('overflow', 'auto', 'important');
            document.body.style.setProperty('overflow', 'auto', 'important');
            // Remove noscroll classes
            document.documentElement.classList.remove('noscroll', 'no-scroll', 'tp-modal-open', 'tp-active');
            document.body.classList.remove('noscroll', 'no-scroll', 'tp-modal-open', 'tp-active');
            // Expand article content containers that paywalls truncate
            document.querySelectorAll('[style*="max-height"]').forEach(function(el) {
                if (el.querySelector('p') || el.querySelector('h2')) {
                    el.style.maxHeight = 'none';
                    el.style.overflow = 'visible';
                }
            });
            // Expand truncated article bodies (Verge/Vox Media style)
            document.querySelectorAll('[class*="duet--article"] [style*="overflow"]').forEach(function(el) {
                el.style.overflow = 'visible';
                el.style.maxHeight = 'none';
            });
            // Remove gradient fade overlays paywalls use to tease content
            document.querySelectorAll('[style*="linear-gradient"]').forEach(function(el) {
                if (el.offsetHeight < 200) el.style.display = 'none';
            });
        }
        killPaywall();
        setTimeout(killPaywall, 1500);
        setTimeout(killPaywall, 3000);

        // Hide raw JSON error text (e.g., broken Facebook/Instagram oEmbed)
        function hideJSONErrors() {
            if (!document.body) return;
            var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
            while (walker.nextNode()) {
                var text = walker.currentNode.textContent.trim();
                if (text.length > 20 && text.indexOf('"error"') !== -1 && text.indexOf('"message"') !== -1) {
                    walker.currentNode.parentElement.style.display = 'none';
                }
            }
        }
        setTimeout(hideJSONErrors, 2000);
        setTimeout(hideJSONErrors, 5000);
        setTimeout(killPaywall, 5000);
        // Watch for dynamically inserted paywall — auto-disconnect after 10s
        if (window.MutationObserver && document.body) {
            var calls = 0;
            var obs = new MutationObserver(function() {
                if (++calls > 20) { obs.disconnect(); return; }
                killPaywall();
            });
            obs.observe(document.body, { childList: true, subtree: false });
            setTimeout(function() { obs.disconnect(); }, 10000);
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

        let paywallJS = WKUserScript(
            source: Self.postLoadPaywallKill,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(paywallJS)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator

        var request = URLRequest(url: url)
        if Self.isPaywalled(url) {
            // Paywalled sites often serve full content to search engine crawlers
            request.setValue("Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)", forHTTPHeaderField: "User-Agent")
        } else {
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        }
        webView.load(request)
        return webView
    }

    private static func isPaywalled(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        // Only sites where Googlebot UA actually bypasses the paywall.
        // Hard-paywalled sites (Wired, NYT, WSJ, etc.) verify Google's IP — Googlebot UA won't work.
        // Those go through NativeReaderView's native RSS excerpt instead.
        let paywalled = ["theverge.com", "fortune.com", "arstechnica.com"]
        return paywalled.contains(where: { host == $0 || host.hasSuffix(".\($0)") })
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.navigationDelegate = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinished: onFinished)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let onFinished: (() -> Void)?
        private var hasFinished = false

        init(onFinished: (() -> Void)?) {
            self.onFinished = onFinished
            super.init()
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

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
