import SwiftUI

@main
struct TechFeedApp: App {
    init() {
        ReaderContentRules.precompile()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
