import SwiftUI

struct ContentView: View {
    @StateObject private var parser = FeedParser()

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
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    .refreshable {
                        parser.fetchAllFeeds()
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
                }
            }
        }
        .onAppear {
            parser.fetchAllFeeds()
        }
    }
}

struct FeedRowView: View {
    let item: FeedItem

    var body: some View {
        Link(destination: item.url) {
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
                        thumbnailPlaceholder
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

                    if !item.description.isEmpty {
                        Text(item.description)
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
                        Text(item.pubDate.relativeTimeString())
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

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

// MARK: - Relative Time

extension Date {
    func relativeTimeString() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
