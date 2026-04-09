import SwiftUI

struct WeeklyDigestView: View {
    let items: [FeedItem]
    @Environment(\.dismiss) private var dismiss

    private var topSources: [(String, Int)] {
        var counts: [String: Int] = [:]
        for item in items {
            counts[item.source, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
    }

    private var topCategories: [(String, Int)] {
        var counts: [String: Int] = [:]
        for item in items {
            counts[item.category, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
    }

    private var trendingStories: [FeedItem] {
        items.filter { $0.isTrending }.prefix(5).map { $0 }
    }

    private var totalSources: Int {
        Set(items.map { $0.source }).count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.bar.fill")
                                .font(.caption)
                                .foregroundColor(.arcaOrange)
                            Text("FEED DIGEST")
                                .font(.caption.weight(.heavy))
                                .foregroundColor(.arcaOrange)
                                .tracking(0.5)
                        }

                        Text("Your Feed at a Glance")
                            .font(.title2.weight(.bold))

                        Text("\(items.count) stories from \(totalSources) sources")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)

                    Divider().padding(.horizontal)

                    // Stats grid
                    HStack(spacing: 12) {
                        statCard(value: "\(items.count)", label: "Stories", icon: "newspaper.fill")
                        statCard(value: "\(totalSources)", label: "Sources", icon: "globe")
                        statCard(value: "\(trendingStories.count)", label: "Trending", icon: "flame.fill")
                    }
                    .padding(.horizontal)

                    // Top categories
                    if !topCategories.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Top Categories")
                                .font(.headline)
                                .padding(.horizontal)

                            VStack(spacing: 8) {
                                ForEach(topCategories, id: \.0) { category, count in
                                    HStack {
                                        Text(category)
                                            .font(.subheadline.weight(.medium))

                                        Spacer()

                                        // Bar
                                        let maxCount = topCategories.first?.1 ?? 1
                                        GeometryReader { geo in
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color.arcaGradient)
                                                .frame(width: geo.size.width * CGFloat(count) / CGFloat(maxCount))
                                        }
                                        .frame(width: 100, height: 8)

                                        Text("\(count)")
                                            .font(.caption.weight(.bold))
                                            .foregroundColor(.arcaOrange)
                                            .frame(width: 30, alignment: .trailing)
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }

                    // Top sources
                    if !topSources.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Most Active Sources")
                                .font(.headline)
                                .padding(.horizontal)

                            VStack(spacing: 8) {
                                ForEach(Array(topSources.enumerated()), id: \.offset) { idx, pair in
                                    HStack(spacing: 12) {
                                        Text("\(idx + 1)")
                                            .font(.caption.weight(.heavy))
                                            .foregroundColor(.white)
                                            .frame(width: 24, height: 24)
                                            .background(idx == 0 ? Color.arcaRed : Color.arcaOrange.opacity(0.7))
                                            .clipShape(Circle())

                                        Text(pair.0)
                                            .font(.subheadline.weight(.medium))

                                        Spacer()

                                        Text("\(pair.1) stories")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }

                    // Trending stories
                    if !trendingStories.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 6) {
                                Image(systemName: "flame.fill")
                                    .foregroundColor(.arcaRed)
                                Text("Trending This Week")
                                    .font(.headline)
                            }
                            .padding(.horizontal)

                            VStack(spacing: 8) {
                                ForEach(trendingStories) { item in
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.title)
                                                .font(.caption.weight(.semibold))
                                                .lineLimit(2)

                                            HStack(spacing: 4) {
                                                Text(item.source)
                                                    .font(.caption2.weight(.medium))
                                                    .foregroundColor(.arcaOrange)
                                                Text("\(item.sourceCount) sources")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }

                                        Spacer()
                                    }
                                    .padding(12)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.arcaOrange)
                }
            }
        }
    }

    private func statCard(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.arcaOrange)
            Text(value)
                .font(.title2.weight(.bold))
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
