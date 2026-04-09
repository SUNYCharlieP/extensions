import Foundation
import AuthenticationServices

/// Manages Sign in with Apple authentication and iCloud sync.
/// No backend required — stores the Apple user identifier in UserDefaults
/// and gates cloud sync on sign-in state.
class AppleSignInManager: NSObject, ObservableObject {
    static let shared = AppleSignInManager()

    private let defaults = UserDefaults.standard
    private let userIDKey = "arca_apple_user_id"
    private let userNameKey = "arca_apple_user_name"
    private let userEmailKey = "arca_apple_user_email"

    @Published var isSignedIn: Bool = false
    @Published var userName: String = ""
    @Published var userEmail: String = ""

    private override init() {
        super.init()
        loadCachedUser()
        checkCredentialState()
    }

    // MARK: - Sign In

    /// Handle the result from a SignInWithAppleButton's onCompletion closure.
    func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            let userID = credential.user

            // Apple only sends name/email on first sign-in.
            // On subsequent sign-ins these are nil — use cached values.
            if let fullName = credential.fullName {
                let name = [fullName.givenName, fullName.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                if !name.isEmpty {
                    userName = name
                    defaults.set(name, forKey: userNameKey)
                }
            }

            if let email = credential.email {
                userEmail = email
                defaults.set(email, forKey: userEmailKey)
            }

            defaults.set(userID, forKey: userIDKey)
            isSignedIn = true
            syncBookmarksFromCloud()

        case .failure:
            // User cancelled or error — do nothing
            break
        }
    }

    // MARK: - Credential State Check

    /// Verify the Apple ID credential is still valid on launch.
    func checkCredentialState() {
        guard let userID = defaults.string(forKey: userIDKey) else { return }

        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { [weak self] state, _ in
            DispatchQueue.main.async {
                switch state {
                case .authorized:
                    break // Still valid — keep signed in
                case .revoked, .notFound:
                    self?.signOut()
                case .transferred:
                    // User transferred to a new device — re-authenticate
                    self?.signOut()
                @unknown default:
                    break
                }
            }
        }
    }

    // MARK: - Sign Out

    func signOut() {
        isSignedIn = false
        userName = ""
        userEmail = ""
        defaults.removeObject(forKey: userIDKey)
        defaults.removeObject(forKey: userNameKey)
        defaults.removeObject(forKey: userEmailKey)
    }

    // MARK: - Cloud Sync

    /// Sync bookmarks to iCloud Key-Value Store (simple, no backend needed).
    func syncBookmarksToCloud() {
        guard isSignedIn else { return }
        let bookmarks = Array(BookmarkManager.shared.bookmarkedURLs)
        NSUbiquitousKeyValueStore.default.set(bookmarks, forKey: "arca_cloud_bookmarks")
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    /// Pull bookmarks from iCloud Key-Value Store.
    func syncBookmarksFromCloud() {
        guard isSignedIn else { return }
        NSUbiquitousKeyValueStore.default.synchronize()
        if let cloudBookmarks = NSUbiquitousKeyValueStore.default.array(forKey: "arca_cloud_bookmarks") as? [String] {
            BookmarkManager.shared.mergeFromCloud(Set(cloudBookmarks))
        }
    }

    /// Sync reading streak to iCloud.
    func syncStreakToCloud() {
        guard isSignedIn else { return }
        let store = NSUbiquitousKeyValueStore.default
        let streak = ReadingStreakManager.shared
        store.set(streak.currentStreak, forKey: "arca_cloud_streak")
        store.set(streak.longestStreak, forKey: "arca_cloud_longest_streak")
        store.set(streak.totalArticlesRead, forKey: "arca_cloud_total_articles")
        store.synchronize()
    }

    // MARK: - Private

    private func loadCachedUser() {
        guard defaults.string(forKey: userIDKey) != nil else { return }
        userName = defaults.string(forKey: userNameKey) ?? ""
        userEmail = defaults.string(forKey: userEmailKey) ?? ""
        isSignedIn = true
    }
}
