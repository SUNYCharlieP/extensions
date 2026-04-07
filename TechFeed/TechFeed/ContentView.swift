import SwiftUI

// MARK: - Main View

struct ContentView: View {
    @StateObject private var parser = FeedParser()
    @State private var selectedItem: FeedItem?
    @State private var hasAppeared = false
    @State private var selectedCategory = "Top Picks"

    private let categories = ["Top Picks", "Apple", "General Tech", "Hacker News", "Security", "Science"]

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
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            parser.fetchAllFeeds()
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

            ArcaLogoView()
                .frame(width: 28, height: 36)
                .padding(.top, 6)
                .padding(.bottom, 10)
        }
        .frame(height: 56)
    }

    // MARK: - Feed Content

    private var filteredItems: [FeedItem] {
        if selectedCategory == "Top Picks" {
            return parser.items
        }
        return parser.items.filter { $0.category == selectedCategory }
    }

    private var feedContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Gradient header
                arcaHeader

                // Category pills
                categoryBar
                    .padding(.top, 4)

                // Hero card
                if let hero = filteredItems.first {
                    HeroCardView(item: hero)
                        .onTapGesture {
                            PreferenceEngine.shared.recordTap(on: hero)
                            selectedItem = hero
                        }
                        .padding(.horizontal)
                        .padding(.top, 16)
                }

                // Remaining articles
                let remaining = Array(filteredItems.dropFirst())

                if selectedCategory == "Top Picks" && !remaining.isEmpty {
                    sectionedFeed(remaining)
                } else {
                    flatFeed(remaining)
                }
            }
            .padding(.bottom, 20)
        }
        .refreshable {
            await parser.fetchAllFeedsAsync()
        }
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

    // MARK: - Sectioned Feed (For You)

    private func sectionedFeed(_ items: [FeedItem]) -> some View {
        let trending = Array(items.prefix(5))
        let rest = Array(items.dropFirst(5))

        let grouped = Dictionary(grouping: rest) { $0.category }
        let orderedCategories = ["Apple", "General Tech", "Hacker News", "Security", "Science"]
            .filter { grouped[$0] != nil }

        return VStack(spacing: 24) {
            // Trending horizontal scroll
            if !trending.isEmpty {
                feedSection(title: "Trending") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(trending) { item in
                                TrendingCardView(item: item)
                                    .onTapGesture {
                                        PreferenceEngine.shared.recordTap(on: item)
                                        selectedItem = item
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }

            // Category groups
            ForEach(orderedCategories, id: \.self) { cat in
                if let catItems = grouped[cat], !catItems.isEmpty {
                    feedSection(title: cat) {
                        VStack(spacing: 10) {
                            ForEach(catItems.prefix(4)) { item in
                                CompactRowView(item: item)
                                    .onTapGesture {
                                        PreferenceEngine.shared.recordTap(on: item)
                                        selectedItem = item
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .padding(.top, 20)
    }

    // MARK: - Flat Feed (Filtered)

    private func flatFeed(_ items: [FeedItem]) -> some View {
        LazyVStack(spacing: 10) {
            ForEach(items) { item in
                CompactRowView(item: item)
                    .onTapGesture {
                        PreferenceEngine.shared.recordTap(on: item)
                        selectedItem = item
                    }
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
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

struct ArcaLoadingView: View {
    @State private var phase: CGFloat = 0

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
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) {
                phase = 1.0
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

// MARK: - Hero Card

struct HeroCardView: View {
    let item: FeedItem
    @State private var isLiked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image
            AsyncImage(url: item.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 200)
                        .clipped()
                case .empty:
                    if item.imageURL != nil {
                        ZStack {
                            heroPlaceholder
                            ProgressView()
                                .tint(.arcaOrange)
                        }
                    } else {
                        heroPlaceholder
                    }
                case .failure:
                    heroPlaceholder
                @unknown default:
                    heroPlaceholder
                }
            }
            .frame(height: 200)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                // Source pill + time + like
                HStack {
                    Text(item.source)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.arcaOrange)
                        .clipShape(Capsule())

                    Spacer()

                    Text(item.pubDate, formatter: Self.relativeFormatter)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            isLiked.toggle()
                        }
                        if isLiked {
                            PreferenceEngine.shared.recordLike(on: item)
                        }
                    } label: {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.subheadline)
                            .foregroundColor(isLiked ? .arcaRed : .secondary.opacity(0.5))
                            .scaleEffect(isLiked ? 1.15 : 1.0)
                    }
                    .buttonStyle(.plain)
                }

                Text(item.title)
                    .font(.headline.weight(.bold))
                    .foregroundColor(.primary)
                    .lineLimit(3)

                if !item.itemDescription.isEmpty {
                    Text(item.itemDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(14)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            isLiked = PreferenceEngine.shared.isLiked(item)
        }
    }

    private var heroPlaceholder: some View {
        SourceInitialView(source: item.source, size: .hero)
            .frame(height: 200)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

// MARK: - Trending Card (Horizontal Scroll)

struct TrendingCardView: View {
    let item: FeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: item.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 200, height: 120)
                        .clipped()
                case .failure, .empty:
                    trendingPlaceholder
                @unknown default:
                    trendingPlaceholder
                }
            }
            .frame(width: 200, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                HStack {
                    Text(item.source)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.arcaOrange)
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(item.pubDate, formatter: Self.relativeFormatter)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(width: 200)
        .padding(.bottom, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var trendingPlaceholder: some View {
        SourceInitialView(source: item.source, size: .trending)
            .frame(width: 200, height: 120)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

// MARK: - Compact Row (Category Sections)

struct CompactRowView: View {
    let item: FeedItem
    @State private var isLiked = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: item.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 64)
                        .clipped()
                case .failure:
                    compactPlaceholder
                case .empty:
                    if item.imageURL != nil {
                        ProgressView()
                            .tint(.arcaOrange)
                            .frame(width: 80, height: 64)
                    } else {
                        compactPlaceholder
                    }
                @unknown default:
                    compactPlaceholder
                }
            }
            .frame(width: 80, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Text(item.source)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.arcaOrange)
                    Text("·")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(item.pubDate, formatter: Self.relativeFormatter)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isLiked.toggle()
                }
                if isLiked {
                    PreferenceEngine.shared.recordLike(on: item)
                }
            } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.subheadline)
                    .foregroundColor(isLiked ? .arcaRed : .secondary.opacity(0.5))
                    .scaleEffect(isLiked ? 1.15 : 1.0)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            isLiked = PreferenceEngine.shared.isLiked(item)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var compactPlaceholder: some View {
        SourceInitialView(source: item.source, size: .compact)
            .frame(width: 80, height: 64)
    }
}

// MARK: - Source Initial Placeholder

enum PlaceholderSize {
    case compact, trending, hero
}

struct SourceInitialView: View {
    let source: String
    let size: PlaceholderSize

    private var initial: String {
        String(source.prefix(1)).uppercased()
    }

    private var colors: (Color, Color) {
        switch source {
        case "Hacker News":     return (Color(red: 1.0, green: 0.4, blue: 0.0), Color(red: 0.85, green: 0.25, blue: 0.0))
        case "Krebs on Security": return (Color(red: 0.2, green: 0.5, blue: 0.8), Color(red: 0.1, green: 0.3, blue: 0.6))
        case "9to5Mac":         return (Color(red: 0.2, green: 0.2, blue: 0.2), Color(red: 0.35, green: 0.35, blue: 0.35))
        case "MacRumors":       return (Color(red: 0.0, green: 0.48, blue: 1.0), Color(red: 0.0, green: 0.35, blue: 0.8))
        case "The Verge":       return (Color(red: 0.5, green: 0.2, blue: 0.8), Color(red: 0.35, green: 0.1, blue: 0.6))
        case "Ars Technica":    return (Color(red: 0.85, green: 0.25, blue: 0.0), Color(red: 0.65, green: 0.15, blue: 0.0))
        case "TechCrunch":      return (Color(red: 0.15, green: 0.7, blue: 0.35), Color(red: 0.1, green: 0.5, blue: 0.25))
        case "MIT Technology Review": return (Color(red: 0.8, green: 0.0, blue: 0.2), Color(red: 0.6, green: 0.0, blue: 0.15))
        default:                return (.arcaOrange, .arcaRed)
        }
    }

    private var fontSize: Font {
        switch size {
        case .compact: return .title2.weight(.heavy)
        case .trending: return .largeTitle.weight(.heavy)
        case .hero: return .system(size: 56, weight: .heavy)
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [colors.0, colors.1],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Text(initial)
                .font(fontSize)
                .foregroundColor(.white.opacity(0.9))
        }
    }
}
