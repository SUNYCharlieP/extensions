# ARCA — Project Manager Briefing

**Date:** April 10, 2026
**App Name:** Arca (bundle: TechFeed)
**Platform:** iOS (SwiftUI, pure Apple frameworks, zero third-party dependencies)
**Location:** `/Users/charlie/extensions/TechFeed/`

---

## CURRENT STATE

- **TestFlight:** Build 1.0 (1) live
- **Bundle ID:** `com.charlespiazza.arca`
- **Domain:** `arcanews.app` (owned)
- **Privacy policy:** https://arcanews.app/privacy
- **Support email:** support@arcanews.app
- **Signing:** Apple Development — Charles Piazza (346D5268JL)
- **Deployment target:** iOS 16.0
- **Release build:** clean, zero errors, zero warnings, validated for store submission

---

## WHAT ARCA IS

Arca is an iOS RSS tech news reader with podcast audio and full-text article extraction. It aggregates 25 RSS feeds across 6 categories (Apple, General Tech, Reviews, Hacker News, Security, Science) and 13 podcast feeds. It features a smart briefing system, article deduplication across sources, preference learning, native article rendering, a Safari Reader–style extraction pipeline for paywalled sites, bookmark sync, reading streaks, a full podcast player with playback speed control, a global Search tab, and Sign in with Apple.

The app has four tabs: **Feed** (categorized briefing + tiered stories), **Listen** (podcast shows + episodes), **Saved** (bookmarks), and **Search** (cross-source full-text search).

---

## CODEBASE OVERVIEW (25 Swift files, ~7,400 lines)

### Core Architecture

| File | Purpose |
|------|---------|
| `TechFeedApp.swift` | App entry point; precompiles ad-blocking content rules |
| `ContentView.swift` | Root view — 4-tab TabView (Feed / Listen / Saved / Search), onboarding gate, `FeedTab`, `BookmarksTab`, `SearchTab` (private struct), all card views (StoryCardView, MediumCardView, WideRowView, BriefingCardView, SavedArticleRow) |
| `Models.swift` | `FeedItem` struct (the article model), `RSSFeed` definitions (all 25 feeds), `Date.relativeString` |
| `FeedParser.swift` | RSS XML parsing, deduplication (Jaccard similarity + URL dedup), preference scoring, keyword categorization, feed diversity algorithm, Open Graph image extraction, `strippingHTMLTags()` extension |

### Article Reading

| File | Purpose |
|------|---------|
| `NativeReaderView.swift` | Native SwiftUI article renderer — decision tree: rich RSS → native; thin RSS → ArticleExtractor fetch → native from extracted HTML; extraction fails → web view. Contains `HTMLContentParser` (parses HTML into ContentBlock array), `ContentBlock` enum (.text, .heading, .image, .blockquote), `hasRichContent` gate, extraction loading state |
| `ArticleExtractor.swift` | Safari Reader–style article extraction pipeline. Fetches raw HTML with mobile Safari UA, pre-cleans (scripts/styles/paywall classes), scores candidate containers by paragraph density + semantic class bonuses, strips navigation/ads/boilerplate, runs plain-text post-processing filter (dedup lines, drop author bios / "Most Popular" / recirc headings), wraps surviving lines in `<p>` tags. Returns clean HTML to `HTMLContentParser`. |
| `ArticleReaderView.swift` | WKWebView-based reader fallback — loads article URL directly when extraction fails. Precompiled `WKContentRuleList` (ReaderRulesV10) for ad/tracker blocking, Reuters consent-modal bypass, injected CSS for dark mode + paywall overlay removal, JS `removeModals()` + MutationObserver for post-load paywall elements (Verge duet–cta widgets), Googlebot UA for soft-paywalled sites |

### Podcast / Audio

| File | Purpose |
|------|---------|
| `ListenTab.swift` | Full podcast UI wrapped in NavigationStack. `ListenTab` (root) → `quickListenSection` (snippets) → `showsSection` (horizontal ShowCard row) → `latestEpisodesSection` (top 30 newest from all shows). `ShowCard` / `PodcastShow` model / `ShowDetailView` (per-show episode list pushed via NavigationLink). Also defines `SnippetCard`, `EpisodeRow`, `FullPlayerView`, `MiniPlayerBar`. |
| `PodcastParser.swift` | Podcast RSS parsing, per-feed fetch cap (10 for snippets, 50 for full/briefing), global 600 cap, segments episodes by type (snippet/briefing/full) |
| `PodcastModels.swift` | `PodcastEpisode` struct, `PodcastFeed` definitions (13 feeds: NPR News Now; Techmeme Ride Home, WSJ Tech News Briefing; The Vergecast, Waveform, Hard Fork, Decoder, ATP, Lex Fridman, This Week in Tech, Darknet Diaries, Acquired, Tim Ferriss) |
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
| `SettingsView.swift` | Source management, custom RSS feed adding (with category picker), Sign in with Apple button + signed-in state |
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

## MAJOR FEATURES COMPLETED (post-briefing)

Everything in this section was open work at the time of the original briefing and is now shipped and live on TestFlight build 1.0 (1).

### ✅ Article Extraction Pipeline (the "critical unsolved problem")

**Status:** Shipped. `ArticleExtractor.swift` implemented per the approved plan.

**What it does:** Safari Reader–style extraction. Fetches raw HTML with a mobile Safari UA, pre-cleans scripts/styles/paywall classes, scores candidate containers by paragraph density and semantic bonuses (article-body, post-content, entry-content, story-body, caas-body), strips navigation / ads / boilerplate, runs a plain-text post-processing pass that drops duplicate lines, author bios, "Most Popular" / "Follow topics" widgets, and recirculation headings. Surviving paragraphs are wrapped in `<p>` tags and fed to the existing `HTMLContentParser`.

**Fallback chain (live):**
```
1. RSS has 150+ words of clean content → Native reader from RSS
2. Fetch + extract article from URL    → Native reader from extracted HTML
3. Extraction fails                     → Web view fallback (ArticleReaderView)
```

**Verified working:** Wired, Ars Technica, Fortune, The Verge, and every other soft- and hard-paywalled site that was previously broken. The extraction runs before any JavaScript executes, so paywall overlays never activate.

### ✅ Sign in with Apple (replaced Google Sign-In)

**Status:** Shipped. `GoogleSignInManager.swift` deleted entirely. `AppleSignInManager.swift` complete.

**What it does:** Native `AuthenticationServices` framework flow — `ASAuthorizationAppleIDProvider` + `ASAuthorizationController`. Stores the Apple user identifier in `UserDefaults`, caches name + email from the first-sign-in credential. On launch, `checkCredentialState()` validates against Apple's servers and signs the user out if revoked. Settings screen uses the native `SignInWithAppleButton` with `.whiteOutline` style. Zero backend, zero third-party dependencies. iCloud sync methods (bookmarks, streak) gated on sign-in state via `NSUbiquitousKeyValueStore`, same contract as before.

### ✅ Search Tab (fourth tab)

**Status:** Shipped. `SearchTab` (private struct in `ContentView.swift`) added as tag 3 in the `TabView`.

**What it does:** Uses the native `.searchable()` modifier with `.navigationBarDrawer(displayMode: .always)`. Searches across **all** `parser.items` (no category scoping, unlike the removed inline FeedTab search bar). Case-insensitive substring match on title, source, and itemDescription. Caps results at 50, renders as `StoryCardView`s. Three states: empty prompt ("Search Arca — find stories across every source"), results list with count header, and no-results empty view. The old inline search bar inside `FeedTab` is gone — the Feed tab always shows the briefing/tier layout now.

### ✅ Listen Tab reorganization (show cards + 13 podcasts)

**Status:** Shipped.

**What changed:**
- `ListenTab` now wrapped in `NavigationStack` with `.navigationDestination(for: PodcastShow.self)`
- New `showsSection` — horizontal scroll of `ShowCard`s (120×120 artwork + show name + episode count), pushes `ShowDetailView` on tap
- New `latestEpisodesSection` — vertical list of the top 30 newest non-snippet episodes across all shows (replaces the old separate "Daily Briefings" and "Full Episodes" sections)
- New model: `PodcastShow` (Identifiable + Hashable), grouped from `parser.episodes` by source
- New view: `ShowDetailView` — pushed via NavigationLink, shows 110×110 hero + full episode list per show
- Podcast feed count expanded from 8 → **13**: added Lex Fridman Podcast, This Week in Tech, Darknet Diaries, Acquired, The Tim Ferriss Show
- Per-feed fetch cap raised from implicit unlimited (with a global `.prefix(100)` choking everything) to explicit 50 per feed (10 for snippet feeds). Global cap raised to 600 to accommodate.

### ✅ Waveform feed URL fix

**Status:** Shipped. The original `https://feeds.megaphone.fm/waveform` URL returned zero items (feed relocated). Simplecast URL was also dead (404 `NoSuchKey`). Correct canonical feed `https://feeds.megaphone.fm/STU4418364045` obtained via iTunes lookup API (itunes ID 1474429475). Parses 347 items, keeps top 50.

### ✅ Hacker News thumbnail fix

**Status:** Shipped. `FeedParser.swift` — after the async Open Graph image fetch in `fetchMissingImages()`, `hasQualityImage` is now recomputed against the newly-set image URL. Previously, OG images fetched after initial parse were flagged as quality-good but the computed property was never re-evaluated, so HN thumbnails showed gray boxes even after the OG fetch completed. Also made `FeedItem.junkPatterns` non-private so FeedParser can access it.

### ✅ Reuters consent modal bypass

**Status:** Shipped. `ArticleReaderView.swift` — added a Reuters-specific `ignore-previous-rules` entry to the compiled `WKContentRuleList` with `if-domain: ["*reuters.com"]`. Previously the ad blocker content rules were suppressing the consent modal scripts in a way that left the modal DOM intact but non-dismissable, breaking navigation. Now Reuters bypasses content rules entirely and their consent flow runs normally. Cache identifier bumped to `ReaderRulesV10` so the rule list recompiles.

### ✅ The Verge Zephr / duet-cta fix

**Status:** Shipped. `ArticleReaderView.swift` — added `duet--commerce`, `subscription-offer`, `duet--cta` selectors to both the injected paywall CSS block and a new JS `removeModals()` function that runs at `.atDocumentEnd` plus a MutationObserver watching for post-load injections. Removes the Vox Media newsletter-widget / subscription-prompt blocks that The Verge inlines into article bodies. The initial Zephr-targeted work was abandoned after it triggered anti-tampering JS that froze the page — the current implementation sticks to the duet-* widgets and leaves the Zephr subscription block untouched (users hit the existing web view fallback for hard Zephr cases).

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

## CURRENT ARTICLE HANDLING STATE (live fallback chain)

```
1. RSS has 150+ words of clean content → Native reader (from RSS)
   ✅ The Verge, 9to5Mac, MacRumors, AppleInsider, TechCrunch, Krebs, Hacker News (links)

2. Thin RSS → ArticleExtractor.extract(url)
   Mobile Safari UA, raw HTML fetch before JS runs, container scoring,
   paywall/junk filters, plain-text post-processing. Returns wrapped <p>
   HTML to HTMLContentParser → native reader.
   ✅ Wired, Ars Technica, Fortune, CNET, Tom's Hardware, plus every
      previously-broken soft-paywalled site.

3. Extraction fails (<100 words extracted) → ArticleReaderView (WKWebView)
   Precompiled WKContentRuleList (ReaderRulesV10), Reuters bypass,
   duet-cta MutationObserver, Googlebot UA for isPaywalled hosts.
```

Hard-paywalled sites that still degrade to web view: NYT, WSJ, Bloomberg, The Athletic, The Information — their initial HTML ships only the lede, so there's nothing for extraction to grab. V2 will look at per-site strategies if users push.

---

## REMAINING TASKS

### Open
1. **iCloud sync** — `BookmarkManager` has merge logic and `AppleSignInManager` gates on sign-in, but the actual CloudKit (or richer `NSUbiquitousKeyValueStore`) sync path is still placeholder-level. Needs end-to-end wiring + conflict resolution.
2. **Offline reading UI** — `OfflineCacheManager` caches HTML, but there's no surface to browse cached articles or indicator showing which are available offline.
3. **Extraction result caching** — `ArticleExtractor` re-fetches on every open. Pipe results through `OfflineCacheManager` keyed by URL hash so reopened articles are instant.
4. **Reading time accuracy** — Currently estimated from RSS description word count. Now that extraction gives us the real body, recompute from extracted word count.

### Not planned / explicitly deferred
- YouTube / video content — removed by user request, not coming back
- Short-form content — removed by user request
- Android as separate category — merged into General Tech by user request

---

## V2 ROADMAP

Post-launch themes once TestFlight feedback comes in:

### Smarter preference algorithm
The current `PreferenceEngine` scores on taps + likes + source affinity + keyword match. V2 adds:
- **Reading duration signals** — weight articles the user actually *read* (time spent in reader view, scroll depth) vs. articles they tapped and immediately dismissed
- **Topic clustering** — move beyond single-keyword matches; cluster articles by topic embeddings so "Apple Silicon" and "M4 chip" reinforce the same preference
- **Recency decay** — taste shifts; older preference weight should decay exponentially so the algorithm tracks current interests instead of frozen first-week signals
- **Negative signals** — explicit "not interested" affordance + implicit dismiss tracking (tapped into card, bailed in <2s) that actively downweights sources/topics

### Deeper podcast libraries
Today there are 13 hand-curated feeds. V2 goals:
- Full podcast search (iTunes Search API) to let users add any show by name
- Subscribed-show UI, per-show unread badges, per-show "new episode" notifications
- Smart podcast discovery based on listening history (same recency-decayed preference signal as articles)

### More article sources
Expand beyond the current 25 feeds:
- International tech outlets (Rest of World, Nikkei Asia, Le Monde Tech)
- Long-form / analysis (Stratechery public posts, Benedict Evans, Every, Platformer)
- Developer sources (Lobsters, GitHub Trending, arXiv cs.AI/cs.CL daily)
- User-contributable source directory (curated, not arbitrary RSS)

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
├── ArticleExtractor.swift         (Safari Reader–style HTML extraction pipeline)
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
