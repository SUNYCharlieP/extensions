import Foundation

/// Fetches a web page and extracts the main article content from raw HTML.
/// Returns cleaned HTML suitable for HTMLContentParser. No JavaScript executes —
/// paywall overlays that depend on JS never activate.
enum ArticleExtractor {

    // MARK: - Public API

    /// Fetch the page at `url` and extract article content.
    /// Returns cleaned HTML on success, nil if extraction fails or content is too thin.
    static func extract(from url: URL) async -> String? {
        // 1a. Fetch raw HTML
        guard let html = await fetchHTML(from: url) else { return nil }

        // 1b. Pre-clean (strip scripts, styles, comments, paywall elements)
        let cleaned = preclean(html)

        // 1c. Find the best article container
        guard let article = findArticleContainer(in: cleaned) else { return nil }

        // 1d. Clean the extracted container
        let result = cleanExtracted(article)

        // 1e. Validate quality — need at least 100 words of real content
        let text = result.strippingHTMLTags()
        let wordCount = text.split(separator: " ").count

        guard wordCount >= 100 else { return nil }

        return result
    }

    // MARK: - 1a. Fetch

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 15
        config.httpMaximumConnectionsPerHost = 3
        return URLSession(configuration: config)
    }()

    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    private static func fetchHTML(from url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let contentType = http.value(forHTTPHeaderField: "Content-Type"),
              contentType.contains("text/html") || contentType.contains("text/xml"),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              !html.isEmpty
        else { return nil }

        return html
    }

    // MARK: - 1b. Pre-clean

    /// Remove script/style/noscript blocks, HTML comments, and paywall-related elements.
    private static func preclean(_ html: String) -> String {
        var result = html

        // Strip <script>...</script>, <style>...</style>, <noscript>...</noscript>
        let stripTags = ["script", "style", "noscript"]
        for tag in stripTags {
            if let regex = try? NSRegularExpression(
                pattern: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
                options: .caseInsensitive
            ) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        // Strip HTML comments <!-- ... -->
        if let regex = try? NSRegularExpression(pattern: "<!--[\\s\\S]*?-->") {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }

        // Strip elements whose class or id contains paywall-related keywords.
        // These are self-contained divs/sections that overlay or gate content.
        let paywallPatterns = [
            "paywall", "Paywall", "metering", "Metering", "regwall", "Regwall",
            "subscribe-wall", "SubscribeWall", "piano-", "tp-modal", "tp-backdrop",
            "PigeonPaywall", "paywall-overlay", "paywall-bar", "journey-unit",
            "GenericCallout", "overlay-no-scroll", "noscroll",
        ]
        for pattern in paywallPatterns {
            // Match opening tag with the pattern in class/id, through to a likely closing tag.
            // Uses a non-greedy match limited to 5000 chars to avoid catastrophic backtracking.
            let escaped = NSRegularExpression.escapedPattern(for: pattern)
            if let regex = try? NSRegularExpression(
                pattern: "<(?:div|section|aside|dialog|span)[^>]*(?:class|id|data-testid)\\s*=\\s*[\"'][^\"']*\(escaped)[^\"']*[\"'][^>]*>[\\s\\S]{0,5000}?</(?:div|section|aside|dialog|span)>",
                options: .caseInsensitive
            ) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        return result
    }

    // MARK: - 1c. Find article container

    /// Find the best candidate element containing the article body.
    private static func findArticleContainer(in html: String) -> String? {
        // Priority 1: <article> tags — pick the one with the highest score
        if let best = findBestTag("article", in: html), scoreCandidate(best) > 20 {
            return best
        }

        // Priority 2: <main> tag
        if let best = findBestTag("main", in: html), scoreCandidate(best) > 20 {
            return best
        }

        // Priority 3: Score <div> and <section> blocks with semantic class names
        if let best = findBestScoredBlock(in: html) {
            return best
        }

        return nil
    }

    /// Extract all instances of a given tag and return the one with the highest score.
    private static func findBestTag(_ tag: String, in html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "<\(tag)(\\s[^>]*)?>([\\s\\S]*?)</\(tag)>",
            options: .caseInsensitive
        ) else { return nil }

        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        guard !matches.isEmpty else { return nil }

        var bestContent: String?
        var bestScore = 0

        for match in matches {
            guard let range = Range(match.range, in: html) else { continue }
            let content = String(html[range])
            let score = scoreCandidate(content)
            if score > bestScore {
                bestScore = score
                bestContent = content
            }
        }

        return bestContent
    }

    /// Scan for <div> and <section> blocks with article-related class/id names,
    /// then score each and return the best.
    private static func findBestScoredBlock(in html: String) -> String? {
        let semanticClasses = [
            "article-body", "article-content", "article__body", "article__content",
            "post-content", "post-body", "post__content",
            "entry-content", "entry-body",
            "story-body", "story-content",
            "caas-body", "caas-content",
            "content-body", "main-content",
            "body-copy", "body-text",
            "rich-text", "prose",
        ]

        var bestContent: String?
        var bestScore = 0

        for className in semanticClasses {
            let escaped = NSRegularExpression.escapedPattern(for: className)
            guard let regex = try? NSRegularExpression(
                pattern: "<(?:div|section)[^>]*class\\s*=\\s*[\"'][^\"']*\(escaped)[^\"']*[\"'][^>]*>([\\s\\S]*?)</(?:div|section)>",
                options: .caseInsensitive
            ) else { continue }

            let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            for match in matches {
                guard let range = Range(match.range, in: html) else { continue }
                let content = String(html[range])
                let score = scoreCandidate(content)
                if score > bestScore {
                    bestScore = score
                    bestContent = content
                }
            }
        }

        // If no semantic class matched, try role="article" or itemprop="articleBody"
        if bestContent == nil {
            let fallbackPatterns = [
                "role\\s*=\\s*[\"']article[\"']",
                "itemprop\\s*=\\s*[\"']articleBody[\"']",
            ]
            for pattern in fallbackPatterns {
                guard let regex = try? NSRegularExpression(
                    pattern: "<(?:div|section)[^>]*\(pattern)[^>]*>([\\s\\S]*?)</(?:div|section)>",
                    options: .caseInsensitive
                ) else { continue }

                let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
                for match in matches {
                    guard let range = Range(match.range, in: html) else { continue }
                    let content = String(html[range])
                    let score = scoreCandidate(content)
                    if score > bestScore {
                        bestScore = score
                        bestContent = content
                    }
                }
            }
        }

        guard bestScore > 20 else { return nil }
        return bestContent
    }

    // MARK: - Scoring

    /// Score a candidate HTML block by paragraph density, semantic signals, and link density.
    private static func scoreCandidate(_ html: String) -> Int {
        var score = 0

        // Count <p> tags and their text length
        if let pRegex = try? NSRegularExpression(
            pattern: "<p[^>]*>([\\s\\S]*?)</p>",
            options: .caseInsensitive
        ) {
            let matches = pRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            for match in matches {
                guard let innerRange = Range(match.range(at: 1), in: html) else { continue }
                let text = String(html[innerRange]).strippingHTMLTags()
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count > 25 {
                    score += 10 + min(trimmed.count / 50, 10) // max +20 per paragraph
                }
            }
        }

        let lower = html.lowercased()

        // Semantic class/id bonuses
        let goodSignals = [
            "article-body", "article-content", "article__body", "article__content",
            "post-content", "entry-content", "story-body", "caas-body",
            "rich-text", "prose", "articleBody",
        ]
        for signal in goodSignals {
            if lower.contains(signal.lowercased()) { score += 25; break }
        }

        // Negative signals
        let badSignals = [
            "sidebar", "side-bar", "nav-", "navigation",
            "footer", "header", "menu",
            "comment", "related", "recommended",
            "social", "share", "ad-slot", "ad-wrapper", "advertisement",
        ]
        for signal in badSignals {
            if lower.contains(signal) { score -= 30; break }
        }

        // Link density penalty — if >30% of text is inside <a> tags, likely navigation
        let totalText = html.strippingHTMLTags()
        if let aRegex = try? NSRegularExpression(
            pattern: "<a[^>]*>([\\s\\S]*?)</a>",
            options: .caseInsensitive
        ) {
            let aMatches = aRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            var linkTextLength = 0
            for match in aMatches {
                if let range = Range(match.range(at: 1), in: html) {
                    linkTextLength += String(html[range]).strippingHTMLTags().count
                }
            }
            if totalText.count > 0 && Double(linkTextLength) / Double(totalText.count) > 0.3 {
                score -= 40
            }
        }

        return score
    }

    // MARK: - 1d. Clean extracted HTML

    /// Strip non-content elements from the extracted article HTML.
    private static func cleanExtracted(_ html: String) -> String {
        var result = html
        // Remove tags that are never article content (with their inner content)
        let removeTags = ["nav", "footer", "header", "aside", "figure", "figcaption", "form", "button", "svg", "input", "select", "textarea", "iframe"]
        for tag in removeTags {
            if let regex = try? NSRegularExpression(
                pattern: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
                options: .caseInsensitive
            ) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
            // Also remove self-closing variants
            if let regex = try? NSRegularExpression(
                pattern: "<\(tag)[^>]*/?>",
                options: .caseInsensitive
            ) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        // Remove elements with display:none or visibility:hidden inline styles
        if let regex = try? NSRegularExpression(
            pattern: "<[^>]+style\\s*=\\s*[\"'][^\"']*(display\\s*:\\s*none|visibility\\s*:\\s*hidden)[^\"']*[\"'][^>]*>[\\s\\S]*?</[^>]+>",
            options: .caseInsensitive
        ) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }

        // Remove social/share/newsletter signup widgets by class patterns
        let junkClasses = [
            "share", "social", "newsletter", "signup", "sign-up",
            "subscribe", "promo", "promotion", "callout",
            "related-articles", "recommended", "more-stories",
            "outbrain", "taboola",
            "follow-authors", "author-follow", "topic-follow",
            "most-popular", "popular-articles",
            "duet--article", "duet--recirculation", "recirculation",
            "newsletter-subscribe", "c-shortcode-subscribe",
            "author-bio", "author-card", "bio",
            "c-recirculation", "l-col--aside",
            "ad-unit", "native-ad", "sponsored",
        ]
        for cls in junkClasses {
            let escaped = NSRegularExpression.escapedPattern(for: cls)
            if let regex = try? NSRegularExpression(
                pattern: "<(?:div|section|aside)[^>]*class\\s*=\\s*[\"'][^\"']*\(escaped)[^\"']*[\"'][^>]*>[\\s\\S]{0,3000}?</(?:div|section|aside)>",
                options: .caseInsensitive
            ) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        // Strip sections containing "Most Popular", "More Stories", etc. headings.
        // The Verge nests these in deeply-wrapped divs, so we use two passes:
        // Pass 1 matches a parent div/section containing the heading (up to 500 chars before h2).
        // Pass 2 catches any remaining bare heading + trailing list.
        let recircHeadings = ["most popular", "more stories", "popular stories", "recommended"]
        for heading in recircHeadings {
            let escaped = NSRegularExpression.escapedPattern(for: heading)
            if let regex = try? NSRegularExpression(
                pattern: "<(?:div|section)[^>]*>[\\s\\S]{0,500}?<h[23][^>]*>[^<]*\(escaped)[^<]*</h[23]>[\\s\\S]{0,5000}?</(?:div|section)>",
                options: .caseInsensitive
            ) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
            if let regex = try? NSRegularExpression(
                pattern: "<h[23][^>]*>[^<]*\(escaped)[^<]*</h[23]>[\\s\\S]{0,5000}?</(?:div|section|ol|ul)>",
                options: .caseInsensitive
            ) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        // Strip follow/topic boilerplate — found in <span>, <div>, or <p> tags
        let boilerplatePatterns = [
            "Posts from this (?:topic|author)",
            "follow topics",
            "follow authors",
            "added to your daily email",
            "personalized homepage feed",
        ]
        for pattern in boilerplatePatterns {
            if let regex = try? NSRegularExpression(
                pattern: "<(?:div|span|p)[^>]*>[\\s\\S]{0,200}?\(pattern)[\\s\\S]{0,3000}?</(?:div|span|p)>",
                options: .caseInsensitive
            ) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        // Strip photo/image credit lines in any tag (<p>, <cite>, <span>, <div>)
        // Matches "Image: Name / Outlet", "Photo by Name", etc.
        if let regex = try? NSRegularExpression(
            pattern: "<(?:p|cite|span|div)[^>]*>\\s*(?:Photo|Image|Video|Illustration)\\s*(?::|by)\\s*.{3,80}?</(?:p|cite|span|div)>",
            options: .caseInsensitive
        ) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }

        // Strip native ad / advertiser content blocks
        if let regex = try? NSRegularExpression(
            pattern: "<(?:div|a)[^>]*>[\\s\\S]{0,500}?(?:Advertiser Content|native-ad|native_ad)[\\s\\S]{0,2000}?</(?:div|a)>",
            options: .caseInsensitive
        ) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }

        // --- Plain-text post-processing pass ---
        // Regex can't reliably strip deeply nested garbage (3+ div layers).
        // Instead: insert newlines at block boundaries, strip tags, split into lines,
        // filter garbage, wrap survivors in <p>.
        var prepped = result
        // Insert newlines before/after block-level closing tags so text splits properly
        let blockTags = ["p", "div", "section", "article", "h1", "h2", "h3", "h4", "h5", "h6",
                         "li", "blockquote", "pre", "tr", "dt", "dd", "br"]
        for tag in blockTags {
            prepped = prepped.replacingOccurrences(of: "</\(tag)>", with: "</\(tag)>\n", options: .caseInsensitive)
        }
        // Also break on <br> and <br/>
        if let brRegex = try? NSRegularExpression(pattern: "<br\\s*/?>", options: .caseInsensitive) {
            prepped = brRegex.stringByReplacingMatches(
                in: prepped,
                range: NSRange(prepped.startIndex..., in: prepped),
                withTemplate: "\n"
            )
        }
        let plainText = prepped.strippingHTMLTags()
        let lines = plainText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let garbageKeywords = [
            "photo by", "image:", "video:", "illustration by",
            "posts from this", "follow topics", "follow authors",
            "added to your daily email", "personalized homepage feed",
            "see all by", "is a senior", "is a staff", "is a reporter",
            "advertiser content", "native ad", "sponsor logo",
            "story text", "subscribers only", "learn more", "comments",
            "senior gaming editor", "senior editor", "staff writer",
            "contributing editor", "managing editor",
            "recommended video",
        ]

        // Bio-line keywords — always strip regardless of word count
        let bioKeywords = [
            "has been the", "is a senior", "is a staff", "editor at", "reporter at",
        ]

        let standaloneHeadings: Set<String> = [
            "most popular", "more stories", "recommended", "popular stories",
        ]

        var seenLines = Set<String>()
        var filtered: [String] = []
        var skipShortRunCount = 0 // after a recirculation heading, skip trailing short lines

        for line in lines {
            let lower = line.lowercased()
            let wordCount = line.split(separator: " ").count

            // Skip standalone recirculation headings + mark trailing items for skip
            if standaloneHeadings.contains(lower) {
                skipShortRunCount = 10 // skip up to 10 short lines after heading
                continue
            }

            // Skip short lines trailing a recirculation heading (headline list items)
            if skipShortRunCount > 0 && wordCount < 15 {
                skipShortRunCount -= 1
                continue
            }
            skipShortRunCount = 0

            // Skip single-word or single-number lines (UI chrome: "Size", "Width", "*")
            if !line.contains(" ") { continue }

            // Skip bio lines regardless of length
            let isBio = bioKeywords.contains { lower.contains($0) }
            if isBio { continue }

            // Skip lines matching garbage keywords (under 30 words — real paragraphs are longer)
            if wordCount < 30 {
                let isGarbage = garbageKeywords.contains { lower.contains($0) }
                if isGarbage { continue }
            }

            // Skip promo blurbs with compound keyword match (e.g. Fortune 500 Innovation Forum)
            if lower.contains("forum") && lower.contains("innovation") { continue }

            // Skip exact duplicates
            if seenLines.contains(line) { continue }
            seenLines.insert(line)

            filtered.append(line)
        }

        // Strip short lines (under 4 words) from the tail — author names and job titles
        // always appear at the end, never in article body
        while let last = filtered.last, last.split(separator: " ").count < 4 {
            filtered.removeLast()
        }

        // Wrap each surviving line in <p> tags for HTMLContentParser
        result = filtered.map { "<p>\($0)</p>" }.joined(separator: "\n")

        return result
    }
}
