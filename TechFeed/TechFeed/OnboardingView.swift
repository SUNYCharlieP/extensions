import SwiftUI

struct OnboardingView: View {
    @ObservedObject private var sourceManager = SourceManager.shared
    @State private var currentPage = 0
    @State private var selectedCategories: Set<String> = ["Apple", "General Tech", "Hacker News", "Security", "Science"]
    var onComplete: () -> Void

    private let categories: [(name: String, icon: String, description: String)] = [
        ("Apple", "apple.logo", "iPhone, Mac, iOS, WWDC"),
        ("General Tech", "cpu", "The Verge, Ars Technica, TechCrunch"),
        ("Reviews", "star.fill", "PCMag, CNET, Tom's Hardware"),
        ("Hacker News", "terminal", "Developer community picks"),
        ("Security", "lock.shield", "Cybersecurity & threats"),
        ("Science", "atom", "Research & space"),
    ]

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(.systemBackground), Color(.systemGroupedBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    categoriesPage.tag(1)
                    readyPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                // Page indicators + button
                VStack(spacing: 20) {
                    HStack(spacing: 8) {
                        ForEach(0..<3) { i in
                            Capsule()
                                .fill(i == currentPage ? Color.arcaOrange : Color.secondary.opacity(0.3))
                                .frame(width: i == currentPage ? 24 : 8, height: 8)
                                .animation(.spring(response: 0.3), value: currentPage)
                        }
                    }

                    Button {
                        if currentPage < 2 {
                            currentPage += 1
                        } else if selectedCategories.isEmpty {
                            // Require at least one category
                        } else {
                            // Apply category selections — explicitly enable/disable
                            let allCats = categories.map { $0.name }
                            for cat in allCats {
                                let shouldEnable = selectedCategories.contains(cat)
                                for feed in RSSFeed.allFeeds where feed.category == cat {
                                    let isCurrentlyEnabled = sourceManager.isEnabled(feed.name)
                                    if shouldEnable != isCurrentlyEnabled {
                                        sourceManager.toggle(feed.name)
                                    }
                                }
                            }
                            sourceManager.completeOnboarding()
                            onComplete()
                        }
                    } label: {
                        Text(currentPage < 2 ? "Continue" : (selectedCategories.isEmpty ? "Pick at least one" : "Start Reading"))
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background {
                                if currentPage == 2 && selectedCategories.isEmpty {
                                    Color.gray
                                } else {
                                    Color.arcaGradient
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Welcome Page

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            // Logo
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.arcaOrange.opacity(0.15), .arcaRed.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)

                ArcaArchShape()
                    .stroke(
                        LinearGradient(colors: [.arcaOrange, .arcaRed], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .frame(width: 60, height: 72)
            }

            VStack(spacing: 12) {
                Text("Welcome to Arca")
                    .font(.largeTitle.weight(.bold))

                Text("Your intelligent tech news feed.\nCurated from the best sources, zero noise.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Feature bullets
            VStack(alignment: .leading, spacing: 16) {
                featureBullet(icon: "newspaper.fill", title: "Smart Feed", desc: "AI-ranked stories from 11+ sources")
                featureBullet(icon: "flame.fill", title: "Trending", desc: "See what's breaking across sources")
                featureBullet(icon: "rectangle.stack.fill", title: "Deep Dive", desc: "Compare how sources cover the same story")
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)

            Spacer()
            Spacer()
        }
    }

    private func featureBullet(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.arcaOrange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Categories Page

    private var categoriesPage: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("Pick Your Interests")
                    .font(.title2.weight(.bold))
                Text("You can always change these later in settings.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 12) {
                ForEach(categories, id: \.name) { cat in
                    Button {
                        if selectedCategories.contains(cat.name) {
                            selectedCategories.remove(cat.name)
                        } else {
                            selectedCategories.insert(cat.name)
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: cat.icon)
                                .font(.title3)
                                .foregroundColor(selectedCategories.contains(cat.name) ? .white : .arcaOrange)
                                .frame(width: 44, height: 44)
                                .background {
                                    if selectedCategories.contains(cat.name) {
                                        Color.arcaGradient
                                    } else {
                                        Color.arcaOrange.opacity(0.12)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(cat.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.primary)
                                Text(cat.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: selectedCategories.contains(cat.name) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundColor(selectedCategories.contains(cat.name) ? .arcaOrange : .secondary.opacity(0.4))
                        }
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Ready Page

    private var readyPage: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.arcaOrange.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.arcaGradient)
            }

            VStack(spacing: 12) {
                Text("You're All Set")
                    .font(.title2.weight(.bold))

                Text("\(selectedCategories.count) categories selected.\nYour feed will get smarter as you read.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
            Spacer()
        }
    }
}
