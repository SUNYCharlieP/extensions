import SwiftUI
import WebKit

struct ArticleReaderView: View {
    let item: FeedItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ReaderWebView(url: item.url)
                .ignoresSafeArea(edges: .bottom)
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
                            ShareLink(item: item.url) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            Link(destination: item.url) {
                                Image(systemName: "safari")
                            }
                        }
                    }
                }
        }
    }
}

// MARK: - Reader Web View

struct ReaderWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        let contentRules = """
        [
            {
                "trigger": {"url-filter": ".*"},
                "action": {"type": "css-display-none", "selector": "header, footer, nav, .nav, .navbar, .menu, .sidebar, .ad, .ads, .advert, .advertisement, .banner, .cookie, .cookie-banner, .consent, .gdpr, .popup, .modal, .overlay, .newsletter, .subscribe, .subscription, .signup, .sign-up, .social-share, .share-buttons, .related, .recommended, .comments, .comment-section, #comments, .disqus, [class*='cookie'], [class*='consent'], [class*='banner'], [class*='popup'], [class*='newsletter'], [class*='subscribe'], [id*='cookie'], [id*='consent'], [id*='banner'], [id*='popup'], [id*='newsletter'], [id*='subscribe'], .site-header, .site-footer, .global-header, .global-footer, .masthead, .top-bar, .bottom-bar, .sticky-bar, .paywall, .gate, .promo, .promotion, [role='banner'], [role='navigation'], [role='complementary'], [role='contentinfo'], aside"}
            }
        ]
        """

        let group = DispatchGroup()
        group.enter()
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "ReaderRules",
            encodedContentRuleList: contentRules
        ) { ruleList, _ in
            if let ruleList = ruleList {
                config.userContentController.add(ruleList)
            }
            group.leave()
        }
        group.wait()

        let readerCSS = """
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
                @media (prefers-color-scheme: dark) {
                    body {
                        color: #e5e5e5 !important;
                        background: #1c1c1e !important;
                    }
                    img { opacity: 0.9; }
                    a { color: #58a6ff !important; }
                }
                img {
                    max-width: 100% !important;
                    height: auto !important;
                    border-radius: 12px !important;
                    margin: 16px 0 !important;
                }
                h1, h2, h3 {
                    font-weight: 700 !important;
                    line-height: 1.3 !important;
                    margin-top: 24px !important;
                }
                h1 { font-size: 28px !important; }
                h2 { font-size: 22px !important; }
                p { margin: 14px 0 !important; }
                a { color: #007aff !important; }
                figure { margin: 16px 0 !important; padding: 0 !important; }
                figcaption {
                    font-size: 14px !important;
                    color: #8e8e93 !important;
                    margin-top: 8px !important;
                }
                pre, code {
                    font-size: 14px !important;
                    background: #f5f5f5 !important;
                    border-radius: 8px !important;
                    padding: 2px 6px !important;
                    overflow-x: auto !important;
                }
                @media (prefers-color-scheme: dark) {
                    pre, code { background: #2c2c2e !important; }
                }
                blockquote {
                    border-left: 3px solid #007aff !important;
                    padding-left: 16px !important;
                    margin: 16px 0 !important;
                    color: #6e6e73 !important;
                    font-style: italic !important;
                }
                iframe, video { max-width: 100% !important; }
                table { font-size: 15px !important; }
                /* Hide fixed/sticky elements that slip through */
                [style*="position: fixed"], [style*="position:fixed"],
                [style*="position: sticky"], [style*="position:sticky"] {
                    display: none !important;
                }
            `;
            document.head.appendChild(style);
        })();
        """

        let userScript = WKUserScript(
            source: readerCSS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(userScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .always

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        webView.load(request)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
