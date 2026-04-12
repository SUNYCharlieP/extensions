import SwiftUI

struct NativeReaderView: View {
    let item: FeedItem
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var bookmarkManager = BookmarkManager.shared
    @State private var showWebFallback = false
    /// Cached results to avoid re-parsing HTML on every body evaluation
    @State private var cachedRichContent: Bool?
    @State private var cachedBlocks: [ContentBlock]?
    /// Article extraction state (for thin RSS content)
    @State private var extractedBlocks: [ContentBlock] = []
    @State private var isExtracting = false
    @State private var extractionFailed = false

    /// RSS HTML with Zephr subscription widgets stripped.
    private var cleanedHTML: String {
        Self.stripZephrFromHTML(item.contentHTML)
    }

    /// Whether we have enough rich content for native rendering.
    private var hasRichContent: Bool {
        let stripped = cleanedHTML.strippingHTMLTags()
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip boilerplate footer lines before counting real content
        let boilerplatePhrases = [
            "read the full story at",
            "read full article",
            "continue reading at",
            "continue reading on",
            "originally appeared on",
            "originally featured on",
            "read more at",
            "read the rest of this",
            "view the full article",
            "discuss on our forums",
        ]

        let lines = trimmed.components(separatedBy: .newlines)
        let cleanLines = lines.filter { line in
            let lineLower = line.lowercased().trimmingCharacters(in: .whitespaces)
            return !boilerplatePhrases.contains(where: { lineLower.contains($0) })
        }
        let cleanText = cleanLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = cleanText.split(separator: " ").count
        // Need substantial content for a good native reading experience.
        // Thin RSS content triggers article extraction instead.
        guard wordCount >= 150 else { return false }

        // Detect mid-content ellipsis truncation
        let tail = String(cleanText.suffix(max(cleanText.count / 3, 100)))
        if tail.contains("\u{2026}") || tail.contains(" ...") { return false }

        // Detect truncated endings
        if cleanText.hasSuffix("...") || cleanText.hasSuffix("\u{2026}") { return false }
        let terminals: Set<Character> = [".", "!", "?", "\"", "'", "\u{201C}", "\u{201D}", "\u{2018}", "\u{2019}"]
        if let c = cleanText.last, !terminals.contains(c), wordCount < 500 { return false }

        return true
    }

    /// Strip Zephr subscription/paywall widgets from RSS HTML.
    /// The Verge embeds these in content:encoded — they'd render as native text otherwise.
    private static func stripZephrFromHTML(_ html: String) -> String {
        var result = html
        // Match <div>, <section>, or <aside> elements with id or class containing "zephr"
        let tags = ["div", "section", "aside"]
        for tag in tags {
            if let regex = try? NSRegularExpression(
                pattern: "<\(tag)[^>]*(?:id|class)\\s*=\\s*[\"'][^\"']*zephr[^\"']*[\"'][^>]*>[\\s\\S]{0,5000}?</\(tag)>",
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

    /// Parsed blocks — cached after first computation
    private var parsedBlocks: [ContentBlock] {
        if let cached = cachedBlocks { return cached }
        return HTMLContentParser.parse(cleanedHTML, heroImageURL: item.imageURL)
    }

    var body: some View {
        let isRich = cachedRichContent ?? hasRichContent
        Group {
            if isRich {
                // Path 1: Rich RSS content — render immediately
                VStack(spacing: 0) {
                    readerToolbar
                    nativeContent
                }
                .background(Color(.systemBackground))
            } else if !extractedBlocks.isEmpty {
                // Path 2: Extracted content — render natively
                VStack(spacing: 0) {
                    readerToolbar
                    nativeContentFromBlocks(extractedBlocks)
                }
                .background(Color(.systemBackground))
            } else if isExtracting {
                // Path 2 (loading): Extraction in progress
                VStack(spacing: 0) {
                    readerToolbar
                    VStack(spacing: 16) {
                        Spacer()
                        ProgressView()
                            .tint(.arcaOrange)
                        Text("Loading article…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Color(.systemBackground))
            } else {
                // Path 3: Extraction failed or not applicable — web view fallback
                ArticleReaderView(item: item)
            }
        }
        .onAppear {
            if cachedRichContent == nil {
                cachedRichContent = hasRichContent
            }
            if cachedBlocks == nil {
                cachedBlocks = HTMLContentParser.parse(cleanedHTML, heroImageURL: item.imageURL)
            }
        }
        .task {
            // Only run extraction when RSS content is thin
            guard !(cachedRichContent ?? hasRichContent) else { return }
            isExtracting = true
            if let html = await ArticleExtractor.extract(from: item.url) {
                let blocks = HTMLContentParser.parse(html, heroImageURL: item.imageURL)
                if !blocks.isEmpty {
                    extractedBlocks = blocks
                } else {
                    extractionFailed = true
                }
            } else {
                extractionFailed = true
            }
            isExtracting = false
        }
    }

    // MARK: - Toolbar

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

    // MARK: - Native Content

    private var nativeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero image
                if let imageURL = item.imageURL, item.hasQualityImage {
                    CachedAsyncImage(url: imageURL)
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipped()
                }

                // Article header
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Text(item.source)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.arcaOrange)

                        Text("·")
                            .foregroundColor(.secondary)

                        Text(item.pubDate.relativeString)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if item.sourceCount > 1 {
                            Text("·")
                                .foregroundColor(.secondary)
                            Text("\(item.sourceCount) sources")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                Divider()
                    .padding(.horizontal, 20)

                // Article body
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(parsedBlocks.enumerated()), id: \.offset) { _, block in
                        switch block {
                        case .text(let str):
                            Text(str)
                                .font(.body)
                                .lineSpacing(6)
                                .fixedSize(horizontal: false, vertical: true)
                        case .heading(let str):
                            Text(str)
                                .font(.title3.weight(.bold))
                                .padding(.top, 8)
                        case .image(let url):
                            CachedAsyncImage(url: url)
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        case .blockquote(let str):
                            HStack(spacing: 0) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.arcaOrange)
                                    .frame(width: 3)
                                Text(str)
                                    .font(.body.italic())
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 12)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

                // "Continue reading" link
                VStack(spacing: 12) {
                    Divider()
                    Link(destination: item.url) {
                        HStack {
                            Text("Continue reading on \(item.source)")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                        }
                        .foregroundColor(.arcaOrange)
                    }
                    .padding(.vertical, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }


    }

    // MARK: - Native Content from Extracted Blocks

    private func nativeContentFromBlocks(_ blocks: [ContentBlock]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero image
                if let imageURL = item.imageURL, item.hasQualityImage {
                    CachedAsyncImage(url: imageURL)
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipped()
                }

                // Article header
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Text(item.source)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.arcaOrange)

                        Text("·")
                            .foregroundColor(.secondary)

                        Text(item.pubDate.relativeString)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if item.sourceCount > 1 {
                            Text("·")
                                .foregroundColor(.secondary)
                            Text("\(item.sourceCount) sources")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                Divider()
                    .padding(.horizontal, 20)

                // Article body from extracted blocks
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        switch block {
                        case .text(let str):
                            Text(str)
                                .font(.body)
                                .lineSpacing(6)
                                .fixedSize(horizontal: false, vertical: true)
                        case .heading(let str):
                            Text(str)
                                .font(.title3.weight(.bold))
                                .padding(.top, 8)
                        case .image(let url):
                            CachedAsyncImage(url: url)
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        case .blockquote(let str):
                            HStack(spacing: 0) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.arcaOrange)
                                    .frame(width: 3)
                                Text(str)
                                    .font(.body.italic())
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 12)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

                // "View original" link
                VStack(spacing: 12) {
                    Divider()
                    Link(destination: item.url) {
                        HStack {
                            Text("View original on \(item.source)")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                        }
                        .foregroundColor(.arcaOrange)
                    }
                    .padding(.vertical, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - HTML Content Parser

enum ContentBlock {
    case text(String)
    case heading(String)
    case image(URL)
    case blockquote(String)
}

enum HTMLContentParser {
    /// Pre-process HTML to fix lazy-loaded images (data-src → src)
    private static func preprocessHTML(_ html: String) -> String {
        // Replace data-src with src for lazy-loaded images (Fortune, etc.)
        var result = html
        // Pattern: <img ... data-src="URL" ... > where src may be a placeholder
        if let regex = try? NSRegularExpression(pattern: "(<img[^>]*?)\\bdata-src\\s*=\\s*([\"'][^\"']+[\"'])", options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1 src=$2")
        }
        return result
    }

    static func parse(_ html: String, heroImageURL: URL? = nil) -> [ContentBlock] {
        guard !html.isEmpty else { return [] }
        let html = preprocessHTML(html)

        var blocks: [ContentBlock] = []
        var seenImageHosts = Set<String>() // deduplicate images by host+path

        // Track the hero image to avoid duplicating it
        if let hero = heroImageURL {
            seenImageHosts.insert((hero.host ?? "") + hero.path)
        }

        let imgRegex = try? NSRegularExpression(pattern: "<img[^>]+src\\s*=\\s*[\"']([^\"']+)[\"']", options: .caseInsensitive)

        // Split HTML into segments by block tags
        let segments = splitByBlockTags(html)

        for segment in segments {
            let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            // Check for images in this segment — deduplicated
            if let imgRegex = imgRegex {
                let range = NSRange(segment.raw.startIndex..., in: segment.raw)
                let matches = imgRegex.matches(in: segment.raw, range: range)
                for match in matches {
                    if let urlRange = Range(match.range(at: 1), in: segment.raw) {
                        let urlStr = String(segment.raw[urlRange])
                        if let url = URL(string: urlStr), isContentImage(urlStr) {
                            let key = (url.host ?? "") + url.path
                            if !seenImageHosts.contains(key) {
                                seenImageHosts.insert(key)
                                blocks.append(.image(url))
                            }
                        }
                    }
                }
            }

            // Skip junk content
            if isJunkContent(trimmed) { continue }

            switch segment.tag {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                blocks.append(.heading(trimmed))
            case "blockquote":
                blocks.append(.blockquote(trimmed))
            default:
                // Regular paragraph — skip if too short (likely a navigation element)
                if trimmed.count > 20 || blocks.isEmpty {
                    blocks.append(.text(trimmed))
                }
            }
        }

        return blocks
    }

    private struct Segment {
        let tag: String
        let raw: String
        let text: String
    }

    private static func splitByBlockTags(_ html: String) -> [Segment] {
        var segments: [Segment] = []

        // Split on block-level opening tags — simpler and more robust than matching pairs
        let splitPattern = "<(?:p|div|h[1-6]|blockquote|li|br\\s*/?)(?:\\s[^>]*)?>|<br\\s*/?>"
        guard let splitRegex = try? NSRegularExpression(pattern: splitPattern, options: .caseInsensitive) else {
            let stripped = html.strippingHTMLTags()
            if !stripped.isEmpty {
                segments.append(Segment(tag: "p", raw: html, text: stripped))
            }
            return segments
        }

        // Detect which tag each chunk came from
        let tagDetect = try? NSRegularExpression(pattern: "<(p|div|h[1-6]|blockquote|li)", options: .caseInsensitive)

        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)
        let matches = splitRegex.matches(in: html, range: fullRange)

        if matches.isEmpty {
            let stripped = html.strippingHTMLTags()
            if !stripped.isEmpty {
                segments.append(Segment(tag: "p", raw: html, text: stripped))
            }
            return segments
        }

        // Capture content before the first block tag
        if matches[0].range.location > 0 {
            let preTag = nsHTML.substring(with: NSRange(location: 0, length: matches[0].range.location))
            let preText = preTag.strippingHTMLTags().trimmingCharacters(in: .whitespacesAndNewlines)
            if !preText.isEmpty {
                segments.append(Segment(tag: "p", raw: preTag, text: preText))
            }
        }

        for (i, match) in matches.enumerated() {
            let chunkStart = match.range.location + match.range.length
            let chunkEnd = i + 1 < matches.count ? matches[i + 1].range.location : nsHTML.length
            guard chunkEnd > chunkStart else { continue }

            let raw = nsHTML.substring(with: NSRange(location: chunkStart, length: chunkEnd - chunkStart))
            let text = raw.strippingHTMLTags().trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }

            // Determine the tag type from the opening tag
            var tag = "p"
            let tagStr = nsHTML.substring(with: match.range)
            if let tagDetect = tagDetect,
               let m = tagDetect.firstMatch(in: tagStr, range: NSRange(location: 0, length: tagStr.count)),
               let r = Range(m.range(at: 1), in: tagStr) {
                tag = String(tagStr[r]).lowercased()
            }

            segments.append(Segment(tag: tag, raw: raw, text: text))
        }

        return segments
    }

    /// Filter out JSON errors, ads, newsletter prompts, boilerplate, and other cruft
    private static func isJunkContent(_ text: String) -> Bool {
        // JSON error responses embedded in content
        if text.contains("\"error\"") && text.contains("\"message\"") { return true }

        let lower = text.lowercased()

        // RSS boilerplate footers — always filter regardless of length
        let boilerplatePatterns = [
            "read the full story at",
            "read full article",
            "continue reading at",
            "continue reading on",
            "originally appeared on",
            "originally featured on",
            "read more at",
            "view the full article",
            "discuss on our forums",
        ]
        for pattern in boilerplatePatterns {
            if lower.contains(pattern) { return true }
        }

        // Only filter short junk paragraphs — long paragraphs are likely real content
        guard text.count < 200 else { return false }

        // Ad/newsletter/social cruft patterns (short text only)
        let junkPatterns = [
            "sign up for our", "subscribe to our", "subscribe now",
            "download the app", "get the app", "install the app",
            "follow us on twitter", "follow us on facebook", "like us on",
            "advertisement", "sponsored content", "paid partner",
            "click here to", "tap here to",
            "share this article", "share this story",
            "filed under:", "related stories",
            "comments are closed", "leave a comment",
            "affiliate link", "commission from",
            "cookie policy", "terms of service",
            "all rights reserved",
            "you may also like", "recommended for you",
        ]

        for pattern in junkPatterns {
            if lower.contains(pattern) { return true }
        }

        return false
    }

    private static func isContentImage(_ url: String) -> Bool {
        let lower = url.lowercased()
        let junk = ["logo", "icon", "avatar", "favicon", "pixel", "1x1",
                     "tracking", "spacer", "blank", ".svg", ".gif", "data:",
                     "gravatar", "sprite", "badge", "emoji", "button"]
        return !junk.contains(where: { lower.contains($0) })
    }
}
