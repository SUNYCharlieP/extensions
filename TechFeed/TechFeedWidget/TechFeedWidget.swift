import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct TechFeedEntry: TimelineEntry {
    let date: Date
    let stories: [WidgetStory]
}

struct WidgetStory: Identifiable {
    let id = UUID()
    let title: String
    let source: String
    let isTrending: Bool
}

// MARK: - Timeline Provider

struct TechFeedProvider: TimelineProvider {
    func placeholder(in context: Context) -> TechFeedEntry {
        TechFeedEntry(date: Date(), stories: Self.placeholderStories)
    }

    func getSnapshot(in context: Context, completion: @escaping (TechFeedEntry) -> Void) {
        let entry = TechFeedEntry(date: Date(), stories: loadCachedStories())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TechFeedEntry>) -> Void) {
        let stories = loadCachedStories()
        let entry = TechFeedEntry(date: Date(), stories: stories)
        // Refresh every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadCachedStories() -> [WidgetStory] {
        guard let data = UserDefaults(suiteName: "group.com.arca.techfeed")?.data(forKey: "widget_stories"),
              let decoded = try? JSONDecoder().decode([CodableWidgetStory].self, from: data) else {
            return Self.placeholderStories
        }
        return decoded.map { WidgetStory(title: $0.title, source: $0.source, isTrending: $0.isTrending) }
    }

    private static let placeholderStories = [
        WidgetStory(title: "Apple announces new MacBook Pro with M5 chip", source: "9to5Mac", isTrending: true),
        WidgetStory(title: "OpenAI releases GPT-5 with reasoning", source: "TechCrunch", isTrending: false),
        WidgetStory(title: "Critical zero-day vulnerability found in Chrome", source: "Krebs", isTrending: true),
    ]
}

struct CodableWidgetStory: Codable {
    let title: String
    let source: String
    let isTrending: Bool
}

// MARK: - Widget Views

struct TechFeedWidgetEntryView: View {
    var entry: TechFeedProvider.Entry
    @Environment(\.widgetFamily) var family

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good Morning" }
        if hour < 17 { return "Good Afternoon" }
        return "Good Evening"
    }

    var body: some View {
        switch family {
        case .systemSmall:
            smallWidget
        case .systemMedium:
            mediumWidget
        default:
            mediumWidget
        }
    }

    // MARK: - Small Widget

    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.478, blue: 0.239), Color(red: 1.0, green: 0.176, blue: 0.333)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                Text("Arca")
                    .font(.caption2.weight(.heavy))
                    .foregroundColor(.secondary)
            }

            if let story = entry.stories.first {
                VStack(alignment: .leading, spacing: 4) {
                    if story.isTrending {
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 8))
                            Text("TRENDING")
                                .font(.system(size: 8, weight: .heavy))
                        }
                        .foregroundColor(Color(red: 1.0, green: 0.176, blue: 0.333))
                    }

                    Text(story.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(3)

                    Text(story.source)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(Color(red: 1.0, green: 0.478, blue: 0.239))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }

    // MARK: - Medium Widget

    private var mediumWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.478, blue: 0.239), Color(red: 1.0, green: 0.176, blue: 0.333)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(greeting)
                    .font(.caption.weight(.bold))

                Spacer()

                Text(Date(), format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Stories
            ForEach(Array(entry.stories.prefix(3).enumerated()), id: \.element.id) { idx, story in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(idx + 1)")
                        .font(.caption2.weight(.heavy))
                        .foregroundColor(.white)
                        .frame(width: 18, height: 18)
                        .background(
                            idx == 0
                                ? Color(red: 1.0, green: 0.176, blue: 0.333)
                                : Color(red: 1.0, green: 0.478, blue: 0.239).opacity(0.8)
                        )
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text(story.title)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Text(story.source)
                                .font(.caption2)
                                .foregroundColor(Color(red: 1.0, green: 0.478, blue: 0.239))

                            if story.isTrending {
                                HStack(spacing: 1) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 7))
                                    Text("Trending")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .foregroundColor(Color(red: 1.0, green: 0.176, blue: 0.333))
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

// MARK: - Widget Configuration

struct TechFeedWidget: Widget {
    let kind: String = "TechFeedWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TechFeedProvider()) { entry in
            TechFeedWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Arca Feed")
        .description("Top tech stories at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct TechFeedWidgetBundle: WidgetBundle {
    var body: some Widget {
        TechFeedWidget()
    }
}
