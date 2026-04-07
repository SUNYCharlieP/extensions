import SwiftUI

struct ContentView: View {
    @StateObject private var parser = FeedParser()
    @State private var selectedItem: FeedItem?
    @State private var hasAppeared = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if parser.isLoading && parser.items.isEmpty {
                    ProgressView("Loading feeds...")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(parser.items) { item in
                                FeedRowView(item: item)
                                    .onTapGesture {
                                        PreferenceEngine.shared.recordTap(on: item)
                                        selectedItem = item
                                    }
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    .refreshable {
                        await parser.fetchAllFeedsAsync()
                    }
                }
            }
            .navigationTitle("Tech Feed")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        parser.fetchAllFeeds()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(parser.isLoading)
                }
            }
            .fullScreenCover(item: $selectedItem) { item in
                ArticleReaderView(item: item)
            }
        }
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            parser.fetchAllFeeds()
        }
    }
}

// MARK: - Feed Row

struct FeedRowView: View {
    let item: FeedItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: item.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 90, height: 70)
                        .clipped()
                case .failure:
                    thumbnailPlaceholder
                case .empty:
                    if item.imageURL != nil {
                        ProgressView()
                            .frame(width: 90, height: 70)
                    } else {
                        thumbnailPlaceholder
                    }
                @unknown default:
                    thumbnailPlaceholder
                }
            }
            .frame(width: 90, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !item.itemDescription.isEmpty {
                    Text(item.itemDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                HStack {
                    Text(item.source)
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Spacer()
                    Text(item.pubDate, formatter: Self.relativeFormatter)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var thumbnailPlaceholder: some View {
        ZStack {
            Color(.tertiarySystemGroupedBackground)
            Image(systemName: "newspaper.fill")
                .font(.title2)
                .foregroundColor(.secondary)
        }
        .frame(width: 90, height: 70)
    }
}
