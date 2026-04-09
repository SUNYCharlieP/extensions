import SwiftUI
import AuthenticationServices

struct SettingsView: View {
    @ObservedObject private var sourceManager = SourceManager.shared
    @ObservedObject private var signInManager = AppleSignInManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showCategoryPicker = false
    @State private var showAddFeed = false
    @State private var newFeedName = ""
    @State private var newFeedURL = ""
    @State private var newFeedCategory = "General Tech"

    private let categoryOptions = ["Apple", "General Tech", "Hacker News", "Security", "Science", "Reviews"]

    private var groupedFeeds: [(String, [RSSFeed])] {
        let all = RSSFeed.allFeeds
        var groups: [String: [RSSFeed]] = [:]
        for feed in all {
            groups[feed.category, default: []].append(feed)
        }
        let order = ["Apple", "General Tech", "Reviews", "Hacker News", "Security", "Science"]
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
                                    set: { enabled in
                                        if enabled != sourceManager.isEnabled(feed.name) {
                                            sourceManager.toggle(feed.name)
                                        }
                                    }
                                ))
                                .tint(.arcaOrange)
                            }
                        }
                    }
                }

                // Custom feeds
                if !sourceManager.customFeeds.isEmpty {
                    Section(header: Text("Custom Feeds")) {
                        ForEach(sourceManager.customFeeds, id: \.url) { feed in
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
                                    sourceManager.removeCustomFeed(url: feed.url)
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
                        newFeedCategory = "General Tech"
                        showCategoryPicker = true
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

                // Account
                Section(header: Text("Account")) {
                    if signInManager.isSignedIn {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title2)
                                .foregroundColor(.arcaOrange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(signInManager.userName)
                                    .font(.subheadline.weight(.medium))
                                Text(signInManager.userEmail)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Button {
                            signInManager.syncBookmarksToCloud()
                            signInManager.syncStreakToCloud()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundColor(.arcaOrange)
                                Text("Sync to iCloud")
                                    .font(.subheadline)
                            }
                        }
                        Button(role: .destructive) {
                            signInManager.signOut()
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                Text("Sign Out")
                                    .font(.subheadline)
                            }
                        }
                    } else {
                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            signInManager.handleSignInResult(result)
                        }
                        .signInWithAppleButtonStyle(.whiteOutline)
                        .frame(height: 44)
                        Text("Sync bookmarks and reading streak across devices")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
            .confirmationDialog("Choose Category", isPresented: $showCategoryPicker) {
                ForEach(categoryOptions, id: \.self) { cat in
                    Button(cat) {
                        newFeedCategory = cat
                        showAddFeed = true
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Pick a category for the new feed")
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
                Text("Adding to \(newFeedCategory) — enter a name and RSS URL")
            }
        }
    }
}
