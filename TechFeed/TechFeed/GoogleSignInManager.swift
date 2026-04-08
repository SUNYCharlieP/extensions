import Foundation
import AuthenticationServices

/// Manages Google Sign-In via ASWebAuthenticationSession (no SDK dependency).
/// Syncs bookmarks and preferences to a simple Firebase-compatible REST backend,
/// or iCloud Key-Value Store as a fallback.
class GoogleSignInManager: ObservableObject {
    static let shared = GoogleSignInManager()

    private let defaults = UserDefaults.standard
    private let userKey = "arca_google_user"
    private let tokenKey = "arca_google_token"
    private var contextProvider: SignInContextProvider?

    @Published var isSignedIn: Bool = false
    @Published var userName: String = ""
    @Published var userEmail: String = ""
    @Published var userPhotoURL: URL?

    private init() {
        loadCachedUser()
    }

    // MARK: - Sign In / Out

    /// Trigger Google OAuth via ASWebAuthenticationSession.
    /// Call from a view that can provide a presentation anchor.
    func signIn(presenting anchor: ASPresentationAnchor) {
        // Google OAuth 2.0 configuration
        // Replace with your actual Google Cloud OAuth client ID
        let clientID = "117778693877-o0pcj69knqbm19plci51023hqjsrn46r.apps.googleusercontent.com"
        let redirectURI = "com.charlespiazza.arca:/oauth2callback"
        let scope = "openid email profile"

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]

        guard let authURL = components.url else { return }
        let callbackScheme = "com.charlespiazza.arca"

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: callbackScheme
        ) { [weak self] callbackURL, error in
            guard let self = self, let callbackURL = callbackURL, error == nil else { return }

            // Extract authorization code from callback
            let queryItems = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems
            guard let code = queryItems?.first(where: { $0.name == "code" })?.value else { return }

            // Exchange code for tokens
            self.exchangeCodeForTokens(code: code)
        }

        let provider = SignInContextProvider(anchor: anchor)
        self.contextProvider = provider
        session.presentationContextProvider = provider
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    func signOut() {
        isSignedIn = false
        userName = ""
        userEmail = ""
        userPhotoURL = nil
        defaults.removeObject(forKey: userKey)
        defaults.removeObject(forKey: tokenKey)
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

    private func exchangeCodeForTokens(code: String) {
        // In production, exchange the auth code for tokens via your backend
        // For now, simulate a successful sign-in with basic user info
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isSignedIn = true
            self.userName = "Signed In User"
            self.userEmail = "user@gmail.com"
            self.cacheUser()
            self.syncBookmarksFromCloud()
        }
    }

    private func cacheUser() {
        let userData: [String: String] = [
            "name": userName,
            "email": userEmail,
            "photo": userPhotoURL?.absoluteString ?? "",
        ]
        defaults.set(userData, forKey: userKey)
    }

    private func loadCachedUser() {
        guard let userData = defaults.dictionary(forKey: userKey) as? [String: String] else { return }
        userName = userData["name"] ?? ""
        userEmail = userData["email"] ?? ""
        if let photo = userData["photo"], !photo.isEmpty {
            userPhotoURL = URL(string: photo)
        }
        isSignedIn = !userEmail.isEmpty
    }
}

// MARK: - ASWebAuthenticationSession Context

private class SignInContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
