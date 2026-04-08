import SwiftUI
import WebKit

// MARK: - Root Tab View

struct ContentView: View {
    @StateObject private var parser = FeedParser()
    @ObservedObject private var bookmarks = BookmarkManager.shared
    @ObservedObject private var sourceManager = SourceManager.shared
    @State private var selectedTab = 0
    @State private var showOnboarding = false
    @State private var showLaunch = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Group {
                if showOnboarding {
                    OnboardingView {
                        withAnimation {
                            showOnboarding = false
                        }
                        parser.fetchAllFeeds()
                    }
                } else {
                    TabView(selection: $selectedTab) {
                        FeedTab(parser: parser)
                            .tabItem {
                                Image(systemName: "newspaper.fill")
                                Text("Feed")
                            }
                            .tag(0)

                        ShortsTab(parser: parser)
                            .tabItem {
                                Image(systemName: "bolt.circle.fill")
                                Text("Shorts")
                            }
                            .tag(1)

                        BookmarksTab(parser: parser)
                            .tabItem {
                                Image(systemName: "bookmark.fill")
                                Text("Saved")
                            }
                            .tag(2)
                    }
                    .tint(.arcaOrange)
                    .onAppear {
                        parser.fetchAllFeeds()
                        NotificationManager.shared.requestPermission()
                    }
                }
            }
            .opacity(showLaunch ? 0 : 1)

            if showLaunch {
                LaunchScreenView()
                    .transition(.opacity)
            }
        }
        .onAppear {
            if !sourceManager.hasOnboarded {
                showOnboarding = true
            }
            // Dismiss launch screen
            let delay: Double = reduceMotion ? 0.5 : 1.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 0.4)) {
                    showLaunch = false
                }
            }
        }
    }
}

// MARK: - Feed Tab

struct FeedTab: View {
    @ObservedObject var parser: FeedParser
    @State private var selectedItem: FeedItem?
    @State private var selectedCategory = "Top Picks"
    @State private var searchText = ""

    /// Single sheet state prevents iOS sheet-presentation conflicts.
    private enum SheetKind: Identifiable {
        case deepDive(FeedItem)
        case settings
        case digest

        var id: String {
            switch self {
            case .deepDive(let item): return "deepDive-\(item.id)"
            case .settings: return "settings"
            case .digest: return "digest"
            }
        }
    }
    @State private var activeSheet: SheetKind?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let categories = ["Top Picks", "Apple", "General Tech", "Hacker News", "Security", "Science", "Videos", "Shorts"]

    private var isIPad: Bool { sizeClass == .regular }

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            if parser.isLoading && parser.items.isEmpty {
                VStack(spacing: 0) {
                    arcaHeader
                    Spacer()
                    ArcaLoadingView()
                    Spacer()
                }
            } else {
                feedContent
            }
        }
        .fullScreenCover(item: $selectedItem) { item in
            ArticleReaderView(item: item)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .deepDive(let item):
                DeepDiveView(primaryItem: item)
            case .settings:
                SettingsView()
            case .digest:
                WeeklyDigestView(items: parser.items)
            }
        }
    }

    // MARK: - Gradient Header

    private var arcaHeader: some View {
        ZStack {
            LinearGradient(
                colors: [.arcaOrange, Color(red: 1.0, green: 0.33, blue: 0.27), .arcaRed],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)

            HStack {
                Button { activeSheet = .digest } label: {
                    Image(systemName: "chart.bar.fill")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }

                Spacer()

                ArcaLogoView()
                    .frame(width: 28, height: 36)

                Spacer()

                Button { activeSheet = .settings } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .frame(height: 56)
    }

    // MARK: - Time-Aware Feed

    private enum FeedMood {
        case morning, midday, evening

        var sectionTitle: String {
            switch self {
            case .morning: return "Overnight Catches"
            case .midday: return "Breaking Now"
            case .evening: return "Today's Analysis"
            }
        }

        var briefingSubtitle: String {
            switch self {
            case .morning: return "Here's what happened while you slept"
            case .midday: return "The biggest stories right now"
            case .evening: return "Today's top stories at a glance"
            }
        }
    }

    private var currentMood: FeedMood {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return .morning }
        if hour < 17 { return .midday }
        return .evening
    }

    // MARK: - Feed Content

    private var filteredItems: [FeedItem] {
        var items: [FeedItem]
        if selectedCategory == "Top Picks" {
            items = parser.items
        } else {
            items = parser.items.filter { $0.category == selectedCategory }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            items = items.filter {
                $0.title.lowercased().contains(query) ||
                $0.source.lowercased().contains(query) ||
                $0.itemDescription.lowercased().contains(query)
            }
        }
        return items
    }

    // qualityItems is now computed inline in feedContent to avoid redundant recomputation

    private var feedContent: some View {
        // Compute filtered/quality items ONCE per body evaluation
        let filtered = filteredItems
        let quality: [FeedItem] = {
            if selectedCategory == "Videos" || selectedCategory == "Shorts" {
                return filtered.filter { $0.hasQualityImage || $0.isVideo }
            }
            return filtered.filter { $0.hasQualityImage && !$0.isVideo }
        }()
        let videos = filtered.filter { $0.isVideo && !$0.isShort }.prefix(6)
        let briefingItems = Array(quality.prefix(5))
        let briefingShown = briefingItems.count >= 3
        let skipCount = briefingShown ? briefingItems.count : 0
        let top = Array(quality.dropFirst(skipCount).prefix(3))
        let remaining = Array(quality.dropFirst(skipCount + top.count).prefix(12))

        return ScrollView {
            LazyVStack(spacing: 0) {
                arcaHeader

                if parser.isLoading && !parser.items.isEmpty {
                    ArcaRefreshIndicator(reduceMotion: reduceMotion)
                        .transition(.opacity)
                }

                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search stories...", text: $searchText)
                        .font(.subheadline)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.top, 8)

                categoryBar
                    .padding(.top, 4)

                // ── Smart Briefing ──
                if briefingShown {
                    BriefingCardView(items: briefingItems, subtitle: currentMood.briefingSubtitle, onTap: { item in
                        tapAction(item)
                    })
                        .padding(.horizontal)
                        .padding(.top, 16)
                }

                // ── Tier 1: Top 3 big stories ──
                if !top.isEmpty {
                    feedSection(title: currentMood.sectionTitle) {
                        VStack(spacing: 16) {
                            ForEach(top) { item in
                                VStack(spacing: 0) {
                                    StoryCardView(item: item, onTap: {
                                        tapAction(item)
                                    }, onDeepDive: item.relatedArticles.isEmpty ? nil : {
                                        activeSheet = .deepDive(item)
                                    })

                                    if !item.relatedArticles.isEmpty {
                                        MoreCoverageView(
                                            articles: item.relatedArticles,
                                            onTap: { related in
                                                PreferenceEngine.shared.recordTap(on: related)
                                                selectedItem = related
                                            },
                                            onDeepDive: {
                                                activeSheet = .deepDive(item)
                                            }
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top, 16)
                }

                // ── Video picks ──
                if !videos.isEmpty {
                    feedSection(title: "Tech Videos") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(Array(videos)) { item in
                                    CompactVideoCard(item: item)
                                        .frame(width: 260)
                                        .onTapGesture { tapAction(item) }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.top, 20)
                }

                // ── Tier 2: Mixed layout ──
                if !remaining.isEmpty {
                    mixedLayoutSection(items: remaining)
                        .padding(.top, 24)
                }
            }
            .padding(.bottom, 20)
        }
        .refreshable {
            await parser.fetchAllFeedsAsync()
        }
    }

    // MARK: - Mixed Layout (varied card sizes)

    /// Layout blocks for the mixed section — precomputed from item list.
    private enum LayoutBlock: Identifiable {
        case pair(FeedItem, FeedItem)
        case triple(FeedItem, FeedItem, FeedItem)
        case wide(FeedItem)

        var id: String {
            switch self {
            case .pair(let a, let b): return "\(a.id)-\(b.id)"
            case .triple(let a, let b, let c): return "\(a.id)-\(b.id)-\(c.id)"
            case .wide(let a): return a.id
            }
        }
    }

    private func buildLayoutBlocks(_ items: [FeedItem]) -> [LayoutBlock] {
        var blocks: [LayoutBlock] = []
        var i = 0
        var blockCount = 0

        // iPad: use 3-column grid; iPhone: pair → pair → wide pattern
        if isIPad {
            while i < items.count {
                if i + 2 < items.count {
                    blocks.append(.triple(items[i], items[i + 1], items[i + 2]))
                    i += 3
                } else if i + 1 < items.count {
                    blocks.append(.pair(items[i], items[i + 1]))
                    i += 2
                } else {
                    blocks.append(.wide(items[i]))
                    i += 1
                }
                blockCount += 1
            }
            return blocks
        }

        // iPhone pattern: pair → pair → wide
        while i < items.count {
            let patternPos = blockCount % 3
            if patternPos < 2 && i + 1 < items.count {
                blocks.append(.pair(items[i], items[i + 1]))
                i += 2
            } else {
                blocks.append(.wide(items[i]))
                i += 1
            }
            blockCount += 1
        }
        return blocks
    }

    private func tapAction(_ item: FeedItem) {
        PreferenceEngine.shared.recordTap(on: item)
        ReadingStreakManager.shared.recordRead()
        ReadStateManager.shared.markRead(item)
        selectedItem = item
    }

    private func mixedLayoutSection(items: [FeedItem]) -> some View {
        let blocks = buildLayoutBlocks(items)

        return VStack(spacing: 14) {
            ForEach(blocks) { block in
                switch block {
                case .pair(let a, let b):
                    HStack(alignment: .top, spacing: 12) {
                        MediumCardView(item: a)
                            .onTapGesture { tapAction(a) }
                        MediumCardView(item: b)
                            .onTapGesture { tapAction(b) }
                    }
                case .triple(let a, let b, let c):
                    HStack(alignment: .top, spacing: 12) {
                        MediumCardView(item: a)
                            .onTapGesture { tapAction(a) }
                        MediumCardView(item: b)
                            .onTapGesture { tapAction(b) }
                        MediumCardView(item: c)
                            .onTapGesture { tapAction(c) }
                    }
                case .wide(let item):
                    WideRowView(item: item)
                        .onTapGesture { tapAction(item) }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Category Bar

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategory = cat
                        }
                    } label: {
                        Text(cat)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(
                                selectedCategory == cat
                                    ? AnyShapeStyle(.arcaGradient)
                                    : AnyShapeStyle(Color(.tertiarySystemGroupedBackground))
                            )
                            .foregroundColor(selectedCategory == cat ? .white : .secondary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Section Header

    private func feedSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.bold))
                .padding(.horizontal)
            content()
        }
    }
}

// MARK: - Bookmarks Tab

struct BookmarksTab: View {
    @ObservedObject var parser: FeedParser
    @ObservedObject private var bookmarks = BookmarkManager.shared
    @State private var selectedItem: FeedItem?

    private var savedItems: [FeedItem] {
        parser.items.filter { bookmarks.isBookmarked($0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if savedItems.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("No saved articles yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Tap the bookmark icon on any story to save it here.")
                            .font(.subheadline)
                            .foregroundColor(.secondary.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(savedItems) { item in
                                SavedArticleRow(item: item)
                                    .onTapGesture {
                                        selectedItem = item
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Saved")
            .fullScreenCover(item: $selectedItem) { item in
                ArticleReaderView(item: item)
            }
        }
    }
}

struct SavedArticleRow: View {
    let item: FeedItem

    var body: some View {
        HStack(spacing: 14) {
            // Image
            Color(.tertiarySystemGroupedBackground)
                .frame(width: 80, height: 80)
                .overlay(
                    CachedAsyncImage(url: item.imageURL)
                        .scaledToFill()
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.source)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.arcaOrange)

                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(item.pubDate.relativeString)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button {
                        withAnimation {
                            BookmarkManager.shared.toggle(item)
                        }
                    } label: {
                        Image(systemName: "bookmark.fill")
                            .font(.caption)
                            .foregroundColor(.arcaOrange)
                    }
                    .buttonStyle(.plain)

                    ShareLink(item: item.url) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Shorts Tab (Full-Screen Vertical Swipe)

struct ShortsTab: View {
    @ObservedObject var parser: FeedParser
    @State private var currentIndex = 0
    @State private var hasTriedRefresh = false
    /// Track which item IDs we've already recorded taps for this session
    @State private var recordedIDs: Set<String> = []

    private var shortItems: [FeedItem] {
        parser.items.filter { $0.isShort }
    }

    /// Safe index — clamps to valid range
    private var safeIndex: Int {
        guard !shortItems.isEmpty else { return 0 }
        return min(currentIndex, shortItems.count - 1)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if shortItems.isEmpty {
                shortsEmptyState
                    .onAppear {
                        // If no shorts yet and we haven't tried, trigger a refresh
                        if !hasTriedRefresh && !parser.isLoading {
                            hasTriedRefresh = true
                            parser.fetchAllFeeds()
                        }
                    }
            } else {
                // Simple one-at-a-time player — no rotation trick (causes rendering artifacts).
                // Shows current short full-screen with swipe up/down to navigate.
                ShortPlayerPage(
                    item: shortItems[safeIndex],
                    isActive: true
                )
                .id(shortItems[safeIndex].id) // Force new WebView per video
                .ignoresSafeArea()
                .gesture(
                    DragGesture(minimumDistance: 50)
                        .onEnded { value in
                            // Swipe up → next, swipe down → previous
                            if value.translation.height < -50 && currentIndex < shortItems.count - 1 {
                                withAnimation { currentIndex += 1 }
                            } else if value.translation.height > 50 && currentIndex > 0 {
                                withAnimation { currentIndex -= 1 }
                            }
                        }
                )
                .onAppear {
                    let item = shortItems[safeIndex]
                    if !recordedIDs.contains(item.id) {
                        recordedIDs.insert(item.id)
                        PreferenceEngine.shared.recordTap(on: item)
                        ReadingStreakManager.shared.recordRead()
                    }
                    ReadStateManager.shared.markRead(item)
                }
                .onChange(of: currentIndex) { newIndex in
                    guard newIndex >= 0, newIndex < shortItems.count else { return }
                    let item = shortItems[newIndex]
                    if !recordedIDs.contains(item.id) {
                        recordedIDs.insert(item.id)
                        PreferenceEngine.shared.recordTap(on: item)
                        ReadingStreakManager.shared.recordRead()
                    }
                    ReadStateManager.shared.markRead(item)
                }
            }
        }
    }

    private var shortsEmptyState: some View {
        VStack(spacing: 16) {
            if parser.isLoading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
                Text("Loading shorts...")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.7))
            } else {
                Image(systemName: "bolt.circle")
                    .font(.system(size: 48))
                    .foregroundColor(.white.opacity(0.3))
                Text("No shorts yet")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.7))
                Text("Quick tech clips from TechLinked,\nShortCircuit, and more.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button {
                    parser.fetchAllFeeds()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.arcaOrange)
                    .clipShape(Capsule())
                }
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - Single Short Page

private struct ShortPlayerPage: View {
    let item: FeedItem
    let isActive: Bool
    @ObservedObject private var bookmarks = BookmarkManager.shared

    private var isBookmarked: Bool { bookmarks.isBookmarked(item) }

    /// Extract YouTube video ID from the item URL.
    private var videoID: String? {
        // /watch?v=VIDEO_ID (standard YouTube URL from RSS)
        if let components = URLComponents(url: item.url, resolvingAgainstBaseURL: false),
           let vid = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return vid
        }
        // /shorts/VIDEO_ID (direct shorts URL)
        let path = item.url.path
        if path.hasPrefix("/shorts/") {
            let id = String(path.dropFirst("/shorts/".count))
            if !id.isEmpty { return id }
        }
        return nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let videoID = videoID, isActive {
                ShortEmbedWebView(videoID: videoID)
                    .ignoresSafeArea()
            } else if let videoID = videoID {
                // Inactive — show thumbnail as placeholder
                CachedAsyncImage(url: URL(string: "https://img.youtube.com/vi/\(videoID)/maxresdefault.jpg"))
                    .scaledToFill()
                    .ignoresSafeArea()
            }

            // Bottom overlay: title + source + actions
            VStack {
                Spacer()

                HStack(alignment: .bottom, spacing: 16) {
                    // Text info
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.source)
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white.opacity(0.7))

                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Side action buttons
                    VStack(spacing: 20) {
                        Button {
                            bookmarks.toggle(item)
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                                    .font(.title3)
                                Text("Save")
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(.white)
                        }

                        ShareLink(item: item.url) {
                            VStack(spacing: 4) {
                                Image(systemName: "arrowshape.turn.up.right.fill")
                                    .font(.title3)
                                Text("Share")
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(.white)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7), .black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 200)
                    .allowsHitTesting(false),
                    alignment: .bottom
                )
            }
        }
    }
}

// MARK: - YouTube Shorts WebView

#if os(iOS)
private struct ShortEmbedWebView: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator

        loadVideo(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.currentVideoID != videoID {
            context.coordinator.currentVideoID = videoID
            loadVideo(in: webView)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(videoID: videoID)
    }

    private func loadVideo(in webView: WKWebView) {
        let safeID = String(videoID.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
        })
        guard !safeID.isEmpty else { return }

        // Load the YouTube embed URL directly as a request (NOT loadHTMLString).
        // This gives proper origin headers so embeds work, and shows only the
        // clean video player without YouTube's full page chrome.
        guard let url = URL(string: "https://www.youtube.com/embed/\(safeID)?autoplay=1&playsinline=1&controls=1&rel=0&modestbranding=1&loop=1&playlist=\(safeID)") else { return }
        var request = URLRequest(url: url)
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        webView.load(request)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var currentVideoID: String
        init(videoID: String) {
            self.currentVideoID = videoID
            super.init()
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
    }
}
#endif

struct VideoCardView: View {
    let item: FeedItem
    @ObservedObject private var bookmarks = BookmarkManager.shared
    @ObservedObject private var readState = ReadStateManager.shared

    private var isRead: Bool { readState.isRead(item) }
    private var isBookmarked: Bool { bookmarks.isBookmarked(item) }

    /// Extract YouTube video ID from a youtube.com/watch URL.
    private var youtubeThumbURL: URL? {
        // YouTube watch URLs: youtube.com/watch?v=VIDEO_ID
        if let components = URLComponents(url: item.url, resolvingAgainstBaseURL: false),
           let videoID = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return URL(string: "https://img.youtube.com/vi/\(videoID)/maxresdefault.jpg")
        }
        return item.imageURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Video thumbnail with play button overlay
            ZStack {
                Color(.tertiarySystemGroupedBackground)
                    .frame(height: 200)
                    .overlay(
                        CachedAsyncImage(url: youtubeThumbURL ?? item.imageURL)
                            .scaledToFill()
                    )
                    .clipped()

                // Play button overlay
                Circle()
                    .fill(.black.opacity(0.5))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                            .offset(x: 2)
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.caption2)
                        .foregroundColor(.arcaOrange)

                    Text(item.source)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.arcaOrange)

                    Text("·")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(item.pubDate.relativeString)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button {
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        bookmarks.toggle(item)
                    } label: {
                        Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                            .foregroundColor(isBookmarked ? .arcaOrange : .secondary.opacity(0.4))
                    }
                    .buttonStyle(.plain)

                    ShareLink(item: item.url) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                }

                Text(item.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                if !item.itemDescription.isEmpty {
                    Text(item.itemDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Brand Colors

extension Color {
    static let arcaOrange = Color(red: 1.0, green: 0.478, blue: 0.239)
    static let arcaRed = Color(red: 1.0, green: 0.176, blue: 0.333)
    static let arcaGradient = LinearGradient(
        colors: [arcaOrange, arcaRed],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension ShapeStyle where Self == LinearGradient {
    static var arcaGradient: LinearGradient {
        LinearGradient(
            colors: [.arcaOrange, .arcaRed],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Arca Loading Animation

struct ArcaRefreshIndicator: View {
    let reduceMotion: Bool
    @State private var isSpinning = false

    var body: some View {
        HStack(spacing: 8) {
            ArcaArchShape()
                .trim(from: 0, to: 0.6)
                .stroke(
                    LinearGradient(colors: [.arcaOrange, .arcaRed], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .frame(width: 18, height: 22)
                .rotationEffect(.degrees(isSpinning ? 360 : 0))
            Text("Refreshing…")
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                isSpinning = true
            }
        }
    }
}

struct ArcaLoadingView: View {
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                // Outer arch — faded base
                ArcaArchShape()
                    .stroke(
                        Color.arcaOrange.opacity(0.2),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 70, height: 80)

                // Outer arch — sweep highlight
                ArcaArchShape()
                    .trim(from: sweepFrom(phase), to: sweepTo(phase))
                    .stroke(
                        LinearGradient(
                            colors: [.arcaOrange, .arcaRed],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 70, height: 80)

                // Inner arch — faded base
                ArcaArchShape()
                    .stroke(
                        Color.arcaOrange.opacity(0.12),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 38, height: 56)

                // Inner arch — sweep highlight (slightly delayed)
                ArcaArchShape()
                    .trim(from: sweepFrom(phase - 0.12), to: sweepTo(phase - 0.12))
                    .stroke(
                        LinearGradient(
                            colors: [.arcaOrange.opacity(0.7), .arcaRed.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 38, height: 56)

                // Beacon dot at apex
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white, .arcaOrange.opacity(0.6), .arcaOrange.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 8
                        )
                    )
                    .frame(width: 16, height: 16)
                    .opacity(beaconOpacity(phase))
                    .offset(y: -40)
            }

            Text("Loading your feed")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
        }
        .onAppear {
            if reduceMotion {
                phase = 0.5 // Static midpoint
            } else {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) {
                    phase = 1.0
                }
            }
        }
    }

    // Sweep travels left → apex → right with a 30% segment length
    private func sweepFrom(_ p: CGFloat) -> CGFloat {
        let t = max(0, p * 1.5 - 0.15)
        return max(0, min(1, t))
    }

    private func sweepTo(_ p: CGFloat) -> CGFloat {
        let t = p * 1.5 - 0.15 + 0.3
        return max(0, min(1, t))
    }

    // Beacon glows when sweep passes the apex (~50% of path)
    private func beaconOpacity(_ p: CGFloat) -> Double {
        let peak = 0.5
        let dist = abs(Double(p) - peak)
        return max(0.1, 1.0 - dist * 3.5)
    }
}

struct ArcaArchShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Pointed gateway arch matching the Arca logo
        path.move(to: CGPoint(x: 0, y: h))
        path.addCurve(
            to: CGPoint(x: w / 2, y: 0),
            control1: CGPoint(x: w * 0.02, y: h * 0.25),
            control2: CGPoint(x: w * 0.25, y: 0)
        )
        path.addCurve(
            to: CGPoint(x: w, y: h),
            control1: CGPoint(x: w * 0.75, y: 0),
            control2: CGPoint(x: w * 0.98, y: h * 0.25)
        )
        return path
    }
}

// MARK: - Logo View (for gradient header)

struct ArcaLogoView: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let inset: CGFloat = 4 // padding so strokes aren't clipped

            let drawW = w - inset * 2
            let drawH = h - inset * 2
            let offsetX = inset
            let offsetY = inset

            // Outer arch
            var outer = Path()
            outer.move(to: CGPoint(x: offsetX, y: offsetY + drawH))
            outer.addCurve(
                to: CGPoint(x: offsetX + drawW / 2, y: offsetY),
                control1: CGPoint(x: offsetX + drawW * 0.02, y: offsetY + drawH * 0.25),
                control2: CGPoint(x: offsetX + drawW * 0.25, y: offsetY)
            )
            outer.addCurve(
                to: CGPoint(x: offsetX + drawW, y: offsetY + drawH),
                control1: CGPoint(x: offsetX + drawW * 0.75, y: offsetY),
                control2: CGPoint(x: offsetX + drawW * 0.98, y: offsetY + drawH * 0.25)
            )
            context.stroke(
                outer,
                with: .color(.white.opacity(0.95)),
                style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
            )

            // Inner arch
            let innerW = drawW * 0.5
            let innerH = drawH * 0.65
            let innerX = offsetX + (drawW - innerW) / 2
            let innerY = offsetY + drawH - innerH

            var inner = Path()
            inner.move(to: CGPoint(x: innerX, y: offsetY + drawH))
            inner.addCurve(
                to: CGPoint(x: innerX + innerW / 2, y: innerY),
                control1: CGPoint(x: innerX + innerW * 0.02, y: innerY + innerH * 0.25),
                control2: CGPoint(x: innerX + innerW * 0.25, y: innerY)
            )
            inner.addCurve(
                to: CGPoint(x: innerX + innerW, y: offsetY + drawH),
                control1: CGPoint(x: innerX + innerW * 0.75, y: innerY),
                control2: CGPoint(x: innerX + innerW * 0.98, y: innerY + innerH * 0.25)
            )
            context.stroke(
                inner,
                with: .color(.white.opacity(0.5)),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )

            // Beacon dot
            let beaconCenter = CGPoint(x: offsetX + drawW / 2, y: offsetY)
            let glowRect = CGRect(x: beaconCenter.x - 4, y: beaconCenter.y - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: glowRect), with: .color(.white.opacity(0.25)))
            let dotRect = CGRect(x: beaconCenter.x - 2, y: beaconCenter.y - 2, width: 4, height: 4)
            context.fill(Path(ellipseIn: dotRect), with: .color(.white.opacity(0.9)))
        }
    }
}

// MARK: - Smart Briefing Card

struct BriefingCardView: View {
    let items: [FeedItem]
    var subtitle: String = "Your daily briefing"
    var onTap: ((FeedItem) -> Void)? = nil
    @ObservedObject private var streak = ReadingStreakManager.shared

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good Morning" }
        if hour < 17 { return "Good Afternoon" }
        return "Good Evening"
    }

    private var trendingCount: Int {
        items.filter { $0.isTrending }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                // Arca mini logo
                ArcaArchShape()
                    .stroke(
                        LinearGradient(
                            colors: [.arcaOrange, .arcaRed],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: 16, height: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(greeting)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(Date(), format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
            }

            Divider()

            // Summary bullets
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.prefix(5).enumerated()), id: \.element.id) { idx, item in
                    Button {
                        onTap?(item)
                    } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(idx + 1)")
                            .font(.caption.weight(.heavy))
                            .foregroundColor(.white)
                            .frame(width: 20, height: 20)
                            .background(
                                idx == 0 ? Color.arcaRed : Color.arcaOrange.opacity(0.8)
                            )
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.primary)
                                .lineLimit(2)

                            HStack(spacing: 4) {
                                Text(item.source)
                                    .font(.caption2.weight(.medium))
                                    .foregroundColor(.arcaOrange)

                                if item.isTrending {
                                    HStack(spacing: 2) {
                                        Image(systemName: "flame.fill")
                                            .font(.system(size: 8))
                                        Text("Trending")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    .foregroundColor(.arcaRed)
                                }
                            }
                        }
                    }
                    }
                    .buttonStyle(.plain)
                }
            }

            // Footer
            HStack {
                if trendingCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.caption2)
                            .foregroundColor(.arcaRed)
                        Text("\(trendingCount) trending \(trendingCount == 1 ? "story" : "stories") right now")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Reading streak
                if streak.currentStreak > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: streak.streakTier.icon)
                            .font(.caption2)
                            .foregroundColor(streak.currentStreak >= 7 ? .arcaRed : .arcaOrange)
                        Text("\(streak.currentStreak) day streak")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(streak.currentStreak >= 7 ? .arcaRed : .arcaOrange)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    LinearGradient(
                        colors: [.arcaOrange.opacity(0.3), .arcaRed.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Story Card (full-width, Apple News style)

struct StoryCardView: View {
    let item: FeedItem
    var onTap: (() -> Void)? = nil
    var onDeepDive: (() -> Void)? = nil
    @ObservedObject private var bookmarks = BookmarkManager.shared
    @ObservedObject private var readState = ReadStateManager.shared
    /// Synced from PreferenceEngine on every render — not stored as @State
    /// to avoid stale values when SwiftUI reuses or recreates the view.
    private var isLiked: Bool { PreferenceEngine.shared.isLiked(item) }
    /// Local animation trigger for the heart scale effect
    @State private var heartBounce = false

    private var isBookmarked: Bool { bookmarks.isBookmarked(item) }
    private var isRead: Bool { readState.isRead(item) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image — tappable to open article (doesn't interfere with action buttons below)
            Button {
                onTap?()
            } label: {
                Color(.tertiarySystemGroupedBackground)
                    .frame(height: 200)
                    .overlay(
                        CachedAsyncImage(url: item.imageURL)
                            .scaledToFill()
                    )
                    .clipped()
            }
            .buttonStyle(.plain)

            // Content
            VStack(alignment: .leading, spacing: 10) {
                // Badges row (only if trending or multi-source)
                if item.isTrending || item.sourceCount > 1 {
                    HStack(spacing: 6) {
                        if item.isTrending {
                            HStack(spacing: 3) {
                                Image(systemName: "flame.fill")
                                    .font(.caption2)
                                Text("TRENDING")
                                    .font(.caption2.weight(.heavy))
                                    .tracking(0.3)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.arcaRed)
                            .clipShape(Capsule())
                        }

                        if item.sourceCount > 1 {
                            Text("\(item.sourceCount) sources")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.arcaOrange)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.arcaOrange.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }

                // Source + time row (separate from badges so it doesn't overflow)
                HStack(spacing: 6) {
                    Text(item.source)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.arcaOrange)

                    Text("·")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(item.pubDate.relativeString)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("·")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("\(item.readingTime) min read")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    // Action buttons
                    HStack(spacing: 14) {
                        Button {
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            if isLiked {
                                PreferenceEngine.shared.removeLike(on: item)
                            } else {
                                PreferenceEngine.shared.recordLike(on: item)
                            }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                heartBounce.toggle()
                            }
                        } label: {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .foregroundColor(isLiked ? .arcaRed : .secondary.opacity(0.4))
                                .scaleEffect(isLiked ? 1.15 : 1.0)
                        }
                        .buttonStyle(.plain)
                        // heartBounce forces SwiftUI to re-evaluate this view
                        // (isLiked reads from non-observable PreferenceEngine)
                        .id(heartBounce)

                        Button {
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()
                            bookmarks.toggle(item)
                        } label: {
                            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                                .foregroundColor(isBookmarked ? .arcaOrange : .secondary.opacity(0.4))
                        }
                        .buttonStyle(.plain)

                        ShareLink(item: item.url) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.secondary.opacity(0.4))
                        }
                    }
                    .font(.subheadline)
                }

                // Title + description — tappable to open article
                Button {
                    onTap?()
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 6) {
                            Text(item.title)
                                .font(.headline.weight(.bold))
                                .foregroundColor(.primary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)

                            if isRead {
                                Text("READ")
                                    .font(.system(size: 8, weight: .heavy))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15))
                                    .clipShape(Capsule())
                                    .padding(.top, 3)
                            }
                        }

                        if !item.itemDescription.isEmpty {
                            Text(item.itemDescription)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                .buttonStyle(.plain)

                // Deep Dive button
                if let onDeepDive = onDeepDive {
                    Button(action: onDeepDive) {
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.stack.fill")
                                .font(.caption2)
                            Text("Deep Dive — Compare \(item.sourceCount) sources")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundColor(.arcaOrange)
                        .padding(.top, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - More Coverage (grouped duplicate stories)

struct MoreCoverageView: View {
    let articles: [FeedItem]
    let onTap: (FeedItem) -> Void
    var onDeepDive: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Text("MORE COVERAGE")
                    .font(.caption2.weight(.heavy))
                    .foregroundColor(.secondary)
                    .tracking(0.5)

                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 0.5)

                if let onDeepDive = onDeepDive {
                    Button(action: onDeepDive) {
                        HStack(spacing: 3) {
                            Image(systemName: "rectangle.stack.fill")
                                .font(.system(size: 9))
                            Text("Deep Dive")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundColor(.arcaOrange)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Related article links
            ForEach(articles) { article in
                Button {
                    onTap(article)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        if article.id != articles.first?.id {
                            Divider()
                                .padding(.leading, 14)
                        }

                        HStack(alignment: .top, spacing: 8) {
                            Text(article.source)
                                .font(.caption.weight(.bold))
                                .foregroundColor(.arcaOrange)
                                .frame(width: 90, alignment: .leading)
                                .lineLimit(1)

                            Text(article.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(
            .rect(
                topLeadingRadius: 0,
                bottomLeadingRadius: 16,
                bottomTrailingRadius: 16,
                topTrailingRadius: 0
            )
        )
        .padding(.top, -8) // tuck under the card above
    }
}

// MARK: - Medium Card (2-column tile)

struct MediumCardView: View {
    let item: FeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image — overlay pattern prevents .fill from blowing out layout
            Color(.tertiarySystemGroupedBackground)
                .frame(height: 110)
                .overlay(
                    CachedAsyncImage(url: item.imageURL)
                        .scaledToFill()
                )
                .clipped()

            // Text — fixed height so all pairs match
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                Spacer(minLength: 0)

                HStack(spacing: 3) {
                    Text(item.source)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.arcaOrange)
                    Text("·")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(item.pubDate.relativeString)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
            .frame(height: 76)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Compact Video Card (horizontal scroll in feed)

struct CompactVideoCard: View {
    let item: FeedItem

    private var youtubeThumbURL: URL? {
        if let components = URLComponents(url: item.url, resolvingAgainstBaseURL: false),
           let videoID = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return URL(string: "https://img.youtube.com/vi/\(videoID)/maxresdefault.jpg")
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Color(.tertiarySystemGroupedBackground)
                    .frame(height: 146)
                    .overlay(
                        CachedAsyncImage(url: youtubeThumbURL ?? item.imageURL)
                            .scaledToFill()
                    )
                    .clipped()

                Circle()
                    .fill(.black.opacity(0.5))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.caption)
                            .foregroundColor(.white)
                            .offset(x: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.arcaOrange)
                    Text(item.source)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.arcaOrange)
                    Text("·")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(item.pubDate.relativeString)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Wide Row (full-width, text left + image right)

struct WideRowView: View {
    let item: FeedItem

    var body: some View {
        HStack(spacing: 14) {
            // Text content
            VStack(alignment: .leading, spacing: 6) {
                Text(item.source)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.arcaOrange)

                Text(item.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.pubDate.relativeString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)

            // Image
            Color(.tertiarySystemGroupedBackground)
                .frame(width: 120, height: 90)
                .overlay(
                    CachedAsyncImage(url: item.imageURL)
                        .scaledToFill()
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
