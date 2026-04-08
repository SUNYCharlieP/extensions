import Foundation

class ReadingStreakManager: ObservableObject {
    static let shared = ReadingStreakManager()

    private let defaults = UserDefaults.standard
    private let streakKey = "arca_streak_count"
    private let lastReadDateKey = "arca_last_read_date"
    private let longestStreakKey = "arca_longest_streak"
    private let totalArticlesKey = "arca_total_articles_read"

    /// Only currentStreak is @Published — it's the only value read in view bodies.
    /// longestStreak/totalArticlesRead are only shown in settings, read on demand.
    @Published var currentStreak: Int
    var longestStreak: Int
    var totalArticlesRead: Int
    var lastReadDate: Date?

    private init() {
        currentStreak = defaults.integer(forKey: streakKey)
        longestStreak = defaults.integer(forKey: longestStreakKey)
        totalArticlesRead = defaults.integer(forKey: totalArticlesKey)
        if let timestamp = defaults.object(forKey: lastReadDateKey) as? Date {
            lastReadDate = timestamp
        }
        // Check if streak is still valid on launch
        validateStreak()
    }

    /// Call when a user reads an article.
    func recordRead() {
        totalArticlesRead += 1

        let today = Calendar.current.startOfDay(for: Date())

        if let lastDate = lastReadDate {
            let lastDay = Calendar.current.startOfDay(for: lastDate)

            if lastDay == today {
                // Already read today — no streak change
                return
            }

            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
            if lastDay == yesterday {
                // Consecutive day — extend streak
                currentStreak += 1
            } else {
                // Missed a day — reset streak
                currentStreak = 1
            }
        } else {
            // First ever read
            currentStreak = 1
        }

        lastReadDate = Date()
        if currentStreak > longestStreak {
            longestStreak = currentStreak
        }

        persist()
    }

    /// Check if the streak broke (user didn't read yesterday).
    private func validateStreak() {
        guard let lastDate = lastReadDate else {
            currentStreak = 0
            return
        }

        let today = Calendar.current.startOfDay(for: Date())
        let lastDay = Calendar.current.startOfDay(for: lastDate)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        if lastDay < yesterday {
            // Streak broken
            currentStreak = 0
            persist()
        }
    }

    /// Whether the user has read an article today.
    var hasReadToday: Bool {
        guard let lastDate = lastReadDate else { return false }
        return Calendar.current.isDateInToday(lastDate)
    }

    /// Streak milestone — fire, blaze, inferno
    var streakTier: StreakTier {
        switch currentStreak {
        case 0: return .none
        case 1...2: return .spark
        case 3...6: return .fire
        case 7...29: return .blaze
        default: return .inferno
        }
    }

    private func persist() {
        let streak = currentStreak
        let longest = longestStreak
        let total = totalArticlesRead
        let lastDate = lastReadDate
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            self.defaults.set(streak, forKey: self.streakKey)
            self.defaults.set(longest, forKey: self.longestStreakKey)
            self.defaults.set(total, forKey: self.totalArticlesKey)
            self.defaults.set(lastDate, forKey: self.lastReadDateKey)
        }
    }
}

enum StreakTier {
    case none, spark, fire, blaze, inferno

    var icon: String {
        switch self {
        case .none: return "circle"
        case .spark: return "flame"
        case .fire: return "flame.fill"
        case .blaze: return "flame.fill"
        case .inferno: return "flame.fill"
        }
    }

    var label: String {
        switch self {
        case .none: return "Start reading!"
        case .spark: return "Getting started"
        case .fire: return "On fire"
        case .blaze: return "Blazing"
        case .inferno: return "Inferno"
        }
    }
}
