# Arca — Article Extraction Pipeline Plan

## The Problem

Paywalled sites like Wired give ~30 word RSS excerpts. The native reader shows a useless one-paragraph snippet with a "Continue reading" link that goes to a paywall. The Googlebot UA trick doesn't work — Wired/NYT/WSJ verify Google's IP ranges. Users get either a tiny excerpt or a broken paywall page.

## The Solution

Fetch the raw page HTML with a normal browser UA, extract the article content from it (before JS runs, so paywalls can't activate), and render it natively. Same approach as Safari Reader Mode. Most paywalled sites include full article text in the initial HTML for SEO/indexing — the paywall is enforced by JavaScript overlays that we never execute.

## Where Extraction Happens

On-device, at article open time. No server, no API, no proxy.

1. User taps article
2. `URLSession` fetches raw HTML from the article URL (normal mobile Safari UA)
3. Swift code parses the HTML string, finds the main article container, extracts paragraphs/headings/images/blockquotes
4. Strips paywall overlays, modals, truncation CSS — site JS never executes so it can't fight back
5. Hands clean content blocks to the existing `NativeReaderView` SwiftUI rendering

## Files Changed

| File | Action | Why |
|------|--------|-----|
| `ArticleExtractor.swift` | **NEW** | Fetch + extraction logic |
| `NativeReaderView.swift` | **MODIFY** | Integrate extraction, add loading state |
| `project.pbxproj` | **MODIFY** | Add new file to Xcode project |

No other files change. The existing `HTMLContentParser`, `ContentBlock`, `ArticleReaderView`, `FeedParser`, and `Models` stay untouched.

---

## Step 1: Create `ArticleExtractor.swift`

Single new file with one async function:

```swift
enum ArticleExtractor {
    static func extract(from url: URL) async -> String?
    // Returns cleaned HTML string on success, nil on failure.
}
```

### 1a. Fetch raw HTML
- `URLSession` with 15s timeout, standard mobile Safari User-Agent (not Googlebot)
- Validate: HTTP 200, content-type is HTML, body non-empty

### 1b. Pre-clean the HTML
- Strip `<script>`, `<style>`, `<noscript>`, `<!-- comments -->` blocks via regex
- Strip elements with paywall/modal/overlay classes (reuse same class patterns already in ArticleReaderView.swift)

### 1c. Find the article container
- **Priority 1**: Look for `<article>` tag. If multiple, pick the one with the most `<p>` tags.
- **Priority 2**: Look for `<main>` tag.
- **Priority 3**: Score all `<div>`/`<section>` blocks by:
  - Paragraph count & text length (+10 per substantial `<p>`)
  - Semantic class/id bonus (+25 for "article-body", "post-content", "entry-content", "story-body", "caas-body")
  - Negative signals (-30 for "sidebar", "nav", "footer", "comment", "related", "ad-")
  - Link density penalty (if >30% of text is inside `<a>` tags, it's likely navigation)
- Take highest-scoring candidate

### 1d. Clean extracted HTML
- Remove remaining `<nav>`, `<footer>`, `<form>`, `<button>`, `<svg>`, `<input>` tags and their contents
- Remove elements with hidden inline styles (`display:none`, `visibility:hidden`)
- Remove social/share/newsletter widgets
- **Keep**: `<p>`, `<h1>`-`<h6>`, `<blockquote>`, `<img>`, `<a>`, `<em>`, `<strong>`, `<ul>`, `<ol>`, `<li>`, `<figure>`, `<figcaption>`, `<br>`, `<pre>`, `<code>`

### 1e. Validate quality
- Strip all tags, count words
- If < 100 words → return nil (extraction failed, trigger fallback)

---

## Step 2: Modify `NativeReaderView.swift`

### 2a. Add state properties
```swift
@State private var extractedHTML: String?
@State private var isExtracting = false
@State private var extractionFailed = false
```

### 2b. New body logic
```
if hasRichContent (RSS is 150+ words):
    → render natively from RSS (existing path, unchanged)
else if isExtracting:
    → show loading state (hero image + title + spinner)
else if extractedHTML != nil:
    → render natively from extracted HTML via existing HTMLContentParser
else if extractionFailed:
    → ArticleReaderView fallback (existing web view)
else:
    → trigger extraction on appear
```

### 2c. Loading state
Show hero image, title, source, and spinner while extraction runs. After 4 seconds show "Open in Safari" hint. Same visual pattern already used in `ArticleReaderView.readerLoadingState`.

### 2d. Remove nativeOnlyHosts / softPaywalledHosts
These per-site lists become unnecessary. The decision is now universal:
- RSS has enough content? → Use it directly.
- RSS is thin? → Try extraction → Fall back to web view if extraction fails.

### 2e. Update parsedBlocks
When `extractedHTML` is available, parse that instead of `item.contentHTML`:
```swift
private var parsedBlocks: [ContentBlock] {
    let html = extractedHTML ?? item.contentHTML
    return HTMLContentParser.parse(html, heroImageURL: item.imageURL)
}
```

---

## Step 3: Add to Xcode project

Add `ArticleExtractor.swift` to `project.pbxproj` (PBXBuildFile, PBXFileReference, group, Sources build phase).

---

## The Fallback Chain

```
1. RSS has 150+ words of clean content?
   YES → Native reader from RSS
         (The Verge, 9to5Mac, MacRumors, AppleInsider, TechCrunch, etc.)
   NO  → Step 2

2. Fetch + extract article from URL
   SUCCESS (100+ words extracted) → Native reader from extracted content
         (Wired, Bloomberg, NYT, CNET, Tom's Hardware, Engadget, etc.)
   FAIL → Step 3

3. Web view fallback (ArticleReaderView)
   Loads URL in WKWebView with existing ad blocking + paywall CSS/JS removal
         (Last resort for JS-only sites or when extraction can't find content)
```

Every article gets the best possible experience. No site-specific hacks. No Googlebot tricks.

---

## Why This Works for Paywalled Sites

Most paywalled sites (Wired, NYT, WSJ, Bloomberg) include the **full article text in the initial HTML response**. They do this because:

1. **SEO** — Google needs to index the content, and Googlebot renders the initial HTML
2. **Social sharing** — Facebook/Twitter previews use Open Graph tags and initial HTML content
3. **Accessibility** — Screen readers and RSS crawlers need the text

The paywall is enforced by **JavaScript** that runs after page load — it adds overlay divs, hides content with CSS, truncates the article body, and blocks scrolling. Since our extraction fetches the raw HTML and parses it *without executing any JavaScript*, the paywall code never runs. We get the full article text that was always there in the source.

This is exactly how Safari Reader Mode, Mozilla Readability, Pocket, Instapaper, Reeder, and Feedly work.

---

## Verification Plan

Test with these sites after implementation:

| Site | RSS Content | Expected Behavior |
|------|------------|-------------------|
| **Wired** | ~30 words | Extraction gets full article |
| **Ars Technica** | ~100 words | Extraction gets full article |
| **The Verge** | Full article via content:encoded | Uses RSS directly (no extraction needed) |
| **Hacker News** | Title + link only | Extraction runs on linked URL |
| **9to5Mac** | Full article | Uses RSS directly |
| **CNET** | Short excerpt | Extraction gets full article |
| **Tom's Hardware** | Short excerpt | Extraction gets full article |
| **Bloomberg** | ~30 words | Extraction gets full article |
| **Fortune** | ~50 words | Extraction gets full article |

---

## What This Does NOT Change

- RSS feed parsing (FeedParser.swift) — untouched
- Feed display / card views (ContentView.swift) — untouched
- Web view fallback (ArticleReaderView.swift) — untouched, still works as last resort
- Podcast/audio (ListenTab, AudioPlayerManager) — untouched
- Bookmarks, settings, onboarding — untouched
- Any currently working article that renders from rich RSS — untouched
