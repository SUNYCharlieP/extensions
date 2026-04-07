import SwiftUI

// MARK: - Main View

struct ContentView: View {
    @StateObject private var parser = FeedParser()
    @State private var selectedItem: FeedItem?
    @State private var hasAppeared = false
    @State private var selectedCategory = "For You"

    private let categories = ["For You", "Apple", "General Tech", "Hacker News", "Security", "Science"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if parser.isLoading && parser.items.isEmpty {
                    ArcaLoadingView()
                } else {
                    feedContent
                }
            }
            .navigationTitle("Arca")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        parser.fetchAllFeeds()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.arcaOrange)
                    }
                    .disabled(parser.isLoading)
                }
            }
            .fullScreenCover(item: $selectedItem) { item in
                ArticleReaderView(item: item)
            }
        }
        .tint(.arcaOrange)
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            parser.fetchAllFeeds()
        }
    }

    // MARK: - Feed Content

    private var filteredItems: [FeedItem] {
        if selectedCategory == "For You" {
            return parser.items
        }
        return parser.items.filter { $0.category == selectedCategory }
    }

    private var feedContent: some View {
        ScrollView {
            VStack(spacing: 0) {
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

                if selectedCategory == "For You" && !remaining.isEmpty {
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
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
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
        VStack(spacing: 24) {
            ZStack {
                // Outer arch
                ArcaArchShape(openAmount: 0.7)
                    .stroke(
                        LinearGradient(
                            colors: [.arcaOrange.opacity(0.3), .arcaRed.opacity(0.3)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .frame(width: 80, height: 60)

                ArcaArchShape(openAmount: 0.7)
                    .trim(from: phase, to: min(phase + 0.4, 1.0))
                    .stroke(
                        LinearGradient(
                            colors: [.arcaOrange, .arcaRed],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .frame(width: 80, height: 60)

                // Inner arch
                ArcaArchShape(openAmount: 0.7)
                    .stroke(
                        LinearGradient(
                            colors: [.arcaOrange.opacity(0.2), .arcaRed.opacity(0.2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                    .frame(width: 48, height: 36)

                ArcaArchShape(openAmount: 0.7)
                    .trim(from: max(phase - 0.15, 0), to: min(phase + 0.25, 1.0))
                    .stroke(
                        LinearGradient(
                            colors: [.arcaOrange.opacity(0.6), .arcaRed.opacity(0.6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                    .frame(width: 48, height: 36)

                // Apex dot
                Circle()
                    .fill(Color.arcaOrange.opacity(0.4 + 0.6 * sin(Double(phase) * Double.pi * 2)))
                    .frame(width: 7, height: 7)
                    .offset(y: -30)
            }

            Text("Loading your feed")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
    }
}

struct ArcaArchShape: Shape {
    var openAmount: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let bottomY = h
        let topY = h * (1 - openAmount)

        path.move(to: CGPoint(x: 0, y: bottomY))
        path.addQuadCurve(
            to: CGPoint(x: w / 2, y: topY),
            control: CGPoint(x: 0, y: topY)
        )
        path.addQuadCurve(
            to: CGPoint(x: w, y: bottomY),
            control: CGPoint(x: w, y: topY)
        )
        return path
    }
}

// MARK: - Hero Card

struct HeroCardView: View {
    let item: FeedItem

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
                case .failure, .empty:
                    heroPlaceholder
                @unknown default:
                    heroPlaceholder
                }
            }
            .frame(height: 200)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                // Source pill + time
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
    }

    private var heroPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [.arcaOrange.opacity(0.15), .arcaRed.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "newspaper.fill")
                .font(.largeTitle)
                .foregroundStyle(.arcaGradient)
        }
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
        ZStack {
            Color(.tertiarySystemGroupedBackground)
            Image(systemName: "newspaper.fill")
                .font(.title3)
                .foregroundStyle(.arcaGradient)
        }
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
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var compactPlaceholder: some View {
        ZStack {
            Color(.tertiarySystemGroupedBackground)
            Image(systemName: "newspaper.fill")
                .font(.body)
                .foregroundStyle(.arcaGradient)
        }
        .frame(width: 80, height: 64)
    }
}
