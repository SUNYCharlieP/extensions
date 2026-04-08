import SwiftUI

struct SettingsView: View {
    @ObservedObject private var sourceManager = SourceManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showAddFeed = false
    @State private var newFeedName = ""
    @State private var newFeedURL = ""
    @State private var newFeedCategory = "General Tech"

    private let categoryOptions = ["Apple", "General Tech", "Hacker News", "Security", "Science"]

    private var groupedFeeds: [(String, [RSSFeed])] {
        let all = RSSFeed.allFeeds
        var groups: [String: [RSSFeed]] = [:]
        for feed in all {
            groups[feed.category, default: []].append(feed)
        }
        let order = ["Apple", "General Tech", "Hacker News", "Security", "Science"]
        return order.compactMap { cat in
            guard let feeds = groups[cat] else { return nil }
            return (cat, feeds)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // Built-in sources
                ForEach(groupedFeeds, id: \.0) { category, feeds in
                    Section(header: Text(category)) {
                        ForEach(feeds, id: \.name) { feed in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feed.name)
                                        .font(.subheadline.weight(.medium))
                                    Text(feed.url)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Toggle("", isOn: Binding(
                                    get: { sourceManager.isEnabled(feed.name) },
                                    set: { _ in sourceManager.toggle(feed.name) }
                                ))
                                .tint(.arcaOrange)
                            }
                        }
                    }
                }

                // Custom feeds
                if !sourceManager.customFeeds.isEmpty {
                    Section(header: Text("Custom Feeds")) {
                        ForEach(Array(sourceManager.customFeeds.enumerated()), id: \.offset) { idx, feed in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feed.name)
                                        .font(.subheadline.weight(.medium))
                                    Text(feed.url)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Button {
                                    sourceManager.removeCustomFeed(at: idx)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }

                // Add custom feed
                Section {
                    Button {
                        showAddFeed = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.arcaOrange)
                            Text("Add Custom RSS Feed")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.arcaOrange)
                        }
                    }
                }

                // App info
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Sources")
                        Spacer()
                        Text("\(sourceManager.enabledFeeds.count) active")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.arcaOrange)
                }
            }
            .alert("Add RSS Feed", isPresented: $showAddFeed) {
                TextField("Feed Name", text: $newFeedName)
                TextField("Feed URL", text: $newFeedURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Add") {
                    guard !newFeedName.isEmpty,
                          !newFeedURL.isEmpty,
                          URL(string: newFeedURL) != nil else { return }
                    sourceManager.addCustomFeed(name: newFeedName, url: newFeedURL, category: newFeedCategory)
                    newFeedName = ""
                    newFeedURL = ""
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter a name and RSS feed URL")
            }
        }
    }
}
