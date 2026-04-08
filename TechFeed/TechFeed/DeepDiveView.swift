import SwiftUI

/// Side-by-side comparison of how different sources cover the same story.
struct DeepDiveView: View {
    let primaryItem: FeedItem
    @Environment(\.dismiss) private var dismiss
    @State private var selectedArticle: FeedItem?

    private var allSources: [FeedItem] {
        [primaryItem] + primaryItem.relatedArticles
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Story topic header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "rectangle.stack.fill")
                                .font(.caption)
                                .foregroundColor(.arcaOrange)
                            Text("DEEP DIVE")
                                .font(.caption.weight(.heavy))
                                .foregroundColor(.arcaOrange)
                                .tracking(0.5)
                        }

                        Text(primaryItem.title)
                            .font(.title3.weight(.bold))
                            .foregroundColor(.primary)

                        Text("\(allSources.count) sources covering this story")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)

                    Divider()
                        .padding(.horizontal)

                    // Each source's take
                    ForEach(allSources) { article in
                        VStack(alignment: .leading, spacing: 10) {
                            // Source header
                            HStack {
                                Text(article.source)
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.arcaOrange)
                                    .clipShape(Capsule())

                                Text(article.pubDate.relativeString)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                Spacer()

                                // Share
                                ShareLink(item: article.url) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            // Title — how this source frames it
                            Text(article.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.primary)

                            // Description
                            if !article.itemDescription.isEmpty {
                                Text(article.itemDescription)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(4)
                            }

                            // Read button
                            Button {
                                selectedArticle = article
                            } label: {
                                Text("Read full article")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.arcaOrange)
                            }
                        }
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .fullScreenCover(item: $selectedArticle) { article in
                ArticleReaderView(item: article)
            }
        }
    }

}
