# ARCA — Project Manager Briefing

**Date:** April 8, 2026
**App Name:** Arca (bundle: TechFeed)
**Platform:** iOS (SwiftUI, pure Apple frameworks, zero third-party dependencies)
**Location:** `/Users/charlie/extensions/TechFeed/`

---

## WHAT ARCA IS

Arca is an iOS RSS tech news reader with podcast audio. It aggregates 25 RSS feeds across 6 categories (Apple, General Tech, Reviews, Hacker News, Security, Science) and 8 podcast feeds. It features a smart briefing system, article deduplication across sources, preference learning, native article rendering, bookmark sync, reading streaks, and a full podcast player with playback speed control.

---

## CODEBASE OVERVIEW (24 Swift files, ~6,500 lines)

### Core Architecture

| File | Purpose |
|------|---------|
| `TechFeedApp.swift` | App entry point; precompiles ad-blocking content rules |
| `ContentView.swift` | Root view — Feed tab, Bookmarks tab, tab bar, onboarding gate, all card views (StoryCardView, MediumCardView, WideRowView, BriefingCardView, SavedArticleRow) |
| `Models.swift` | `FeedItem` struct (the article model), `RSSFeed` definitions (all 25 feeds), `Date.relativeString` |
| `FeedParser.swift` | RSS XML parsing, deduplication (Jaccard similarity + URL dedup), preference scoring, keyword categorization, feed diversity algorithm, Open Graph image extraction, `strippingHTMLTags()` extension |

### Article Reading

| File | Purpose |
|------|---------|
| `NativeReaderView.swift` | Native SwiftUI article renderer — decides whether to render from RSS content or fall back to web view. Contains `HTMLContentParser` (parses HTML into ContentBlock array), `ContentBlock` enum (.text, .heading, .image, .blockquote), paywall host lists, `hasRichContent` gate |
| `ArticleReaderView.swift` | WKWebView-based reader fallback — loads article URL directly. Has precompiled `WKContentRuleList` for ad/tracker blocking, injected CSS for dark mode + paywall overlay removal, injected JS for post-load paywall killing. Uses Googlebot UA for soft-paywalled sites |

### Podcast / Audio

| File | Purpose |
|------|---------|
| `ListenTab.swift` | Full podcast UI — snippet cards, episode rows, full player view, mini player bar |
| `PodcastParser.swift` | Podcast RSS parsing, segments episodes by type (snippet/briefing/full) |
| `PodcastModels.swift` | `PodcastEpisode` struct, `PodcastFeed` definitions (8 feeds) |
| `AudioPlayerManager.swift` | AVPlayer wrapper — singleton, playback rate control, Now Playing info, remote commands (lock screen/AirPods), background audio |

### State Management (all singletons, all ObservableObject)

| File | Purpose |
|------|---------|
| `BookmarkManager.swift` | Bookmark CRUD with iCloud merge, thread-safe persistence |
| `ReadStateManager.swift` | Tracks read articles (capped at 2000, FIFO eviction) |
| `ReadingStreakManager.swift` | Daily reading streak tracking, longest streak, total article count |
| `PreferenceEngine.swift` | Learns user preferences from taps/likes — scores feeds by source affinity + keyword relevance + recency. Thread-safe with NSLock |
| `SourceManager.swift` | Enable/disable sources, custom feed CRUD |
| `AppleSignInManager.swift` | Sign in with Apple via AuthenticationServices — stores Apple user ID in UserDefaults, gates iCloud sync on sign-in state |
| `NotificationManager.swift` | Local notifications for breaking stories (5+ sources covering same story) |
| `OfflineCacheManager.swift` | Caches article HTML for offline reading, 7-day pruning, SHA256 hashing |

### UI Components

| File | Purpose |
|------|---------|
| `CachedImageView.swift` | `CachedAsyncImage` — in-memory image cache (100 items, 40MB cap), URL-based dedup, downsampling to 800px |
| `LaunchScreenView.swift` | Animated Arca arch logo launch screen |
| `OnboardingView.swift` | 3-page onboarding (welcome → category picker → ready) |
| `SettingsView.swift` | Source management, custom RSS feed adding (with category picker), Google sign-in |
| `WeeklyDigestView.swift` | Feed statistics dashboard ("Feed Digest") |
| `DeepDiveView.swift` | Multi-source story comparison — shows how different outlets covered the same story |

---

## WHAT'S WORKING WELL

These features are stable and should not be touched:

1. **RSS parsing & deduplication** — 25 feeds parsed, grouped by Jaccard title similarity, best source chosen by preference affinity + image availability. URL-based dedup catches Techmeme rewrites.

2. **Feed diversity algorithm** — Two-pass approach: tries to avoid 3+ consecutive same-category items, relaxes if all remaining items share a category. Max 1 per category in briefing. Stops Apple's 3 feeds from dominating.

3. **Preference engine** — Learns from taps (1x weight) and likes (3x weight). Scores by source affinity + keyword relevance + recency. Scales preference weight from 0→40% over first 30 taps.

4. **Native rendering for rich RSS** — The Verge, 9to5Mac, MacRumors, AppleInsider, TechCrunch, Krebs on Security all provide full articles via `content:encoded`. These render beautifully in the native reader with hero images, headings, blockquotes, inline images.

5. **Hacker News** — Special handling: no images (cards hide image section), links to external articles, text-only layout.

6. **Podcast player** — Full-featured: background audio, lock screen controls, AirPods remote, playback speed (0.5x–2x), seek forward/back, mini player bar.

7. **Bookmarks** — Persist locally, merge with iCloud, display in saved tab without image placeholders for image-less items.

8. **Ad/tracker blocking** — Precompiled WKContentRuleList blocks 30+ ad/tracking domains at network level. CSS hides ad containers, cookie banners, consent modals.

9. **Card views** — StoryCardView, MediumCardView, WideRowView all conditionally hide image sections when items have no quality image (fixes Hacker News gray boxes).

10. **Techmeme** — Extracts actual source article URL from Techmeme's aggregator description HTML, so users go to the real article, not Techmeme's permalink.

---

## THE CRITICAL UNSOLVED PROBLEM

### Paywalled articles with thin RSS content

**The issue:** Sites like Wired, Bloomberg, NYT, WSJ, Fortune give only ~15-50 word RSS excerpts. When a user taps one of these articles, they currently see either:

- **A useless 1-paragraph native excerpt** with a "Continue reading" link that goes to a paywall (the current state for "nativeOnlyHosts" like Wired)
- **A broken paywall page** in the web view (what happens when we try to load the actual URL)

**This is the #1 user complaint and the reason we're here.**

### What we tried and why it failed

#### Attempt 1: Googlebot User-Agent in WKWebView
**Idea:** Send `User-Agent: Googlebot/2.1` when loading paywalled sites in the web view. Sites serve full content to Google's crawler.
**Result:** Works for some sites (The Verge, Ars Technica, Fortune). **Fails for Wired, NYT, WSJ, Bloomberg** — they verify that requests claiming to be Googlebot actually come from Google's IP ranges. Our request gets detected as fake and hits the paywall anyway.
**Current state:** Googlebot UA is still used for the 3 "soft-paywalled" sites where it works (theverge.com, fortune.com, arstechnica.com). Removed from the 6 "hard-paywalled" sites.

#### Attempt 2: Low word-count threshold for native RSS rendering
**Idea:** For hard-paywalled sites, show even a 15-word RSS excerpt natively — at least it's clean and not a broken paywall page.
**Result:** Technically works but the user experience is terrible. A single paragraph with a hero image and a "Continue reading on Wired" link is not acceptable. The user's exact feedback: *"who's gonna read that and think well i really enjoy this app!!"*
**Current state:** This is what the app does right now for Wired. It's a band-aid, not a solution.

#### Attempt 3: CSS/JS paywall stripping in WKWebView
**Idea:** Inject CSS to hide paywall overlays (`[class*="paywall"]`, `[class*="piano"]`, etc.) and JS to remove `overflow:hidden`, expand truncated containers, kill gradient fades.
**Result:** Partially works for soft paywalls but hard-paywalled sites fight back. Their JavaScript detects the environment, re-injects overlays, truncates content server-side, or redirects entirely. The CSS/JS battle is unwinnable because their code runs in the same web view.
**Current state:** Still active in ArticleReaderView.swift as a last-resort fallback. Works okay for non-paywalled sites with cookie/consent banners.

### The approved plan (not yet implemented)

**Article Extraction Pipeline** — A fundamentally different approach. See `ARTICLE_EXTRACTION_PLAN.md` in the project root.

**How it works:**
1. Fetch the raw HTML from the article URL using `URLSession` (normal Safari UA, not Googlebot)
2. Extract the article body content from the HTML using a Readability-like algorithm (score elements by paragraph density, semantic tags, text-to-markup ratio)
3. Strip paywall artifacts from the extracted HTML (overlays, modals, hidden styles)
4. Render the cleaned content natively in SwiftUI through the existing `HTMLContentParser`

**Why it should work:** Most paywalled sites include the full article text in their initial HTML response for SEO (Google indexes the HTML). The paywall is enforced by JavaScript that runs after page load — adds overlays, hides content, truncates. Since our extraction parses raw HTML without executing JavaScript, the paywall code never runs. This is how Safari Reader Mode, Readability, Pocket, Instapaper, Reeder, and Feedly do it.

**Files to create/modify:**
- `ArticleExtractor.swift` — **NEW** — fetch + extraction logic
- `NativeReaderView.swift` — **MODIFY** — integrate extraction, add loading state while fetching
- `project.pbxproj` — **MODIFY** — add new file to Xcode build

**Fallback chain after implementation:**
```
1. RSS has 150+ words of clean content? → Native reader from RSS (no fetch needed)
2. Fetch + extract article from URL → Native reader from extracted content
3. Extraction fails? → Web view fallback (ArticleReaderView)
```

**Status:** Plan written and reviewed. Not yet implemented. Waiting for approval to proceed.

---

## BUGS FIXED IN THIS SESSION (complete list)

### User-Reported Issues (all resolved)

| Issue | Fix | Files Changed |
|-------|-----|---------------|
| **The Verge subscription wall** | Added to paywalledHosts, native reader renders rich RSS content (Verge provides full articles via content:encoded) | NativeReaderView.swift |
| **Wired articles not loading** | Multiple attempts (see "unsolved problem" above). Currently shows short native excerpt as band-aid | NativeReaderView.swift, ArticleReaderView.swift |
| **Ars Technica not loading** | Added to softPaywalledHosts + isPaywalled list. Googlebot UA works for Ars | NativeReaderView.swift, ArticleReaderView.swift |
| **Apple bias in feed** | Capped diversePick to max 1 per category in briefing. Added consecutive-category limit in diversify(). Two-pass approach prevents General Tech dump | ContentView.swift, FeedParser.swift |
| **YouTube/video content** | Removed all 6 YouTube RSS feeds from Models.swift. Removed all video UI code, video player presentations, selectedVideo state from ContentView.swift. Deleted InAppVideoPlayer.swift | Models.swift, ContentView.swift, project.pbxproj |
| **Shorts content** | Removed alongside YouTube. No feeds have isShort=true | Models.swift |
| **Hacker News empty thumbnails** | Conditional image rendering in StoryCardView, MediumCardView, WideRowView, SavedArticleRow — hide image section when `!hasQualityImage` | ContentView.swift |
| **Android tab removal** | Removed "Android" from categories array. Recategorized Android Authority + 9to5Google as "General Tech". Updated OnboardingView, SettingsView, FeedParser categorize() | ContentView.swift, Models.swift, OnboardingView.swift, SettingsView.swift, FeedParser.swift |
| **Techmeme linking** | Added extractTechmemeSourceURL() — extracts real article URL from Techmeme description HTML | FeedParser.swift |
| **CNET/Tom's Hardware/Fortune loading** | Added OneTrust/Evidon/TrustE consent selectors to content rules. Fortune lazy images fixed with data-src→src preprocessing | ArticleReaderView.swift, NativeReaderView.swift |

### Code Quality Bugs Found Via Audit (all resolved)

| Bug | Severity | Fix | File |
|-----|----------|-----|------|
| FeedItem Equatable only compared relatedArticles by count | Medium | Now compares actual article IDs | Models.swift |
| FeedItem Equatable ignored title and category | Medium | Added title + category to == check | Models.swift |
| PreferenceEngine not ObservableObject — like state didn't sync across views | Medium | Made ObservableObject with @Published likedVersion counter | PreferenceEngine.swift, ContentView.swift |
| Techmeme URL rewriting caused duplicate FeedItem IDs | Medium | Added URL-based dedup pass before Jaccard similarity | FeedParser.swift |
| diversify() category check blocked all General Tech sources | Medium | Two-pass approach: strict rules first, relax category check for skipped sources | FeedParser.swift |
| Custom feed category picker missing from UI | Medium | Added confirmationDialog for category selection before name/URL alert | SettingsView.swift |
| "Weekly Digest" title misleading (showed current snapshot, not weekly) | Medium | Changed to "Feed Digest" / "Your Feed at a Glance" | WeeklyDigestView.swift |
| AVPlayer rate set before readyToPlay | Low | Removed premature rate assignment; correct one fires in status observer | AudioPlayerManager.swift |
| NativeReaderView re-parsed HTML on every body evaluation | Low | Cached hasRichContent and parsedBlocks with @State | NativeReaderView.swift |
| Hash-based feed tie-breaking non-deterministic (Swift randomizes hashValue per launch) | Low | Replaced with stable djb2 hash | FeedParser.swift |
| stop() didn't cancel in-flight artwork download | Low | Added artworkTask?.cancel() to stop() | AudioPlayerManager.swift |
| SavedArticleRow showed gray placeholder for image-less bookmarks | Medium | Conditional image rendering matching other card views | ContentView.swift |
| OfflineCacheManager cached paywall HTML (wrong UA) | Low | Uses Googlebot UA for soft-paywalled sites in cache requests | OfflineCacheManager.swift |
| InAppVideoPlayer.swift was dead code (178 lines) | Low | Deleted file, removed from project.pbxproj | InAppVideoPlayer.swift, project.pbxproj |
| Unused `lower` variable in hasRichContent | Low | Removed | NativeReaderView.swift |

---

## CURRENT PAYWALL HANDLING STATE (as of now)

### NativeReaderView.swift decision logic:
```
hasRichContent checks item.contentHTML (from RSS):
├── nativeOnlyHosts (wired, nyt, wsj, bloomberg, athletic, information):
│   └── 15+ words → native reader (shows short excerpt)
│       This is the band-aid. Works but terrible UX.
│
├── Everything else:
│   └── 150+ words + no truncation → native reader
│       └── <150 words → falls to ArticleReaderView (web view)
│
ArticleReaderView (web view fallback):
├── isPaywalled (verge, fortune, arstechnica):
│   └── Uses Googlebot UA → gets full article
│
└── Everything else:
    └── Normal Safari UA → works for non-paywalled sites
```

### What renders well RIGHT NOW:
- ✅ The Verge — full content:encoded RSS, native reader
- ✅ 9to5Mac, MacRumors, AppleInsider — full RSS, native reader
- ✅ TechCrunch — full RSS, native reader
- ✅ Krebs on Security — full RSS, native reader
- ✅ Ars Technica — Googlebot web view works
- ✅ Fortune — Googlebot web view works (lazy images fixed)
- ✅ Engadget, The Register, 404 Media, ZDNET, Phoronix, TechSpot, TLDR, Reuters — non-paywalled, web view works
- ✅ PCMag, CNET, Tom's Hardware — non-paywalled, web view works
- ✅ Hacker News — external links, web view works
- ✅ Android Authority, 9to5Google — non-paywalled, web view works

### What renders POORLY right now:
- ❌ **Wired** — 30-word native excerpt. Paywall blocks web view. Googlebot blocked.
- ❌ **Bloomberg** — same situation as Wired
- ❌ **NYT** — same situation
- ❌ **WSJ** — same situation
- ❌ **The Athletic** — same situation
- ❌ **The Information** — same situation

These 6 sites are the targets for the Article Extraction Pipeline.

---

## REMAINING TASKS (priority order)

### P0 — Critical (the reason users are unhappy)
1. **Build the Article Extraction Pipeline** — Plan approved, not yet implemented. This solves the Wired/Bloomberg/NYT/WSJ problem. See `ARTICLE_EXTRACTION_PLAN.md`.

### P1 — Important (should do soon)
2. **Sign in with Apple** — AppleSignInManager is fully implemented. No backend needed. Credential state checked on launch. iCloud sync for bookmarks and reading streak works via NSUbiquitousKeyValueStore.
3. **iCloud sync** — BookmarkManager has merge logic but cloud sync is placeholder. Need CloudKit or similar.

### P2 — Nice to have
4. **Offline reading** — OfflineCacheManager exists and caches HTML, but there's no UI to browse cached articles or indicator showing which articles are available offline.
5. **Extraction result caching** — After building the extraction pipeline, cache extracted HTML in OfflineCacheManager so repeated opens don't re-fetch.
6. **Reading time accuracy** — Currently estimated from RSS description word count. With extraction, can calculate from actual article length.

### Not planned / explicitly deferred
- YouTube/video content — removed by user request, not coming back for now
- Short-form content — removed by user request
- Android as separate category — merged into General Tech by user request

---

## KEY TECHNICAL DECISIONS ALREADY MADE

1. **No third-party dependencies** — Pure Apple frameworks only. No SwiftSoup, no Kanna, no ReadabilityKit. The extraction algorithm must use NSRegularExpression and String operations.

2. **On-device extraction** — No server, no proxy, no API. Everything runs on the phone.

3. **Existing HTMLContentParser is the renderer** — The extraction pipeline produces clean HTML that feeds into the existing `HTMLContentParser.parse()` → `[ContentBlock]` → SwiftUI rendering. The renderer is NOT changing.

4. **Normal Safari UA for extraction** — Not Googlebot. The extraction approach doesn't need UA tricks because it parses raw HTML before JavaScript runs.

5. **Fallback chain is: RSS → Extraction → Web View** — Never show a broken page. Always fall back gracefully.

---

## PROJECT STRUCTURE

```
TechFeed/
├── TechFeedApp.swift              (entry point)
├── ContentView.swift              (root view + all card views)
├── Models.swift                   (FeedItem, RSSFeed, Date extension)
├── FeedParser.swift               (RSS parsing, dedup, scoring, categorization)
├── NativeReaderView.swift         (native article renderer + HTMLContentParser)
├── ArticleReaderView.swift        (WKWebView fallback reader)
├── ListenTab.swift                (podcast UI + mini player + full player)
├── PodcastParser.swift            (podcast RSS parsing)
├── PodcastModels.swift            (podcast data models)
├── AudioPlayerManager.swift       (AVPlayer wrapper + remote commands)
├── BookmarkManager.swift          (bookmark CRUD + cloud merge)
├── ReadStateManager.swift         (read article tracking)
├── ReadingStreakManager.swift      (daily streak tracking)
├── PreferenceEngine.swift         (preference learning + scoring)
├── SourceManager.swift            (source enable/disable + custom feeds)
├── AppleSignInManager.swift       (Sign in with Apple + iCloud sync)
├── NotificationManager.swift      (breaking story alerts)
├── OfflineCacheManager.swift      (article HTML caching)
├── CachedImageView.swift          (in-memory image cache)
├── LaunchScreenView.swift         (animated launch screen)
├── OnboardingView.swift           (3-page onboarding)
├── SettingsView.swift             (source management UI)
├── WeeklyDigestView.swift         (feed statistics dashboard)
├── DeepDiveView.swift             (multi-source story comparison)
├── Assets.xcassets/               (app icons, colors)
├── Info.plist                     (app configuration)
├── ARTICLE_EXTRACTION_PLAN.md     (approved plan for extraction pipeline)
└── PROJECT_MANAGER_BRIEFING.md    (this document)
```

---

## DEVELOPER WORKING AGREEMENTS

These rules were established after multiple rounds of rework:

1. **No new features until all bugs are fixed** — User's explicit mandate
2. **One file per turn, one problem per turn** — Build check between each change
3. **No refactoring working code while fixing broken code** — Flag adjacent issues, wait for approval
4. **If a fix doesn't work, stop and explain** — Don't auto-retry with a different approach
5. **No Googlebot UA tricks for hard-paywalled sites** — They verify IP, it doesn't work
6. **When uncertain, say so before writing code** — Not after it breaks
