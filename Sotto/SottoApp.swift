import SwiftUI
import SwiftData

@main
struct SottoApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var themeManager = ThemeManager.shared
    @State private var lockManager = AppLockManager()

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    SottoMainView()
                } else {
                    OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                }
            }
            .modelContainer(for: JournalEntry.self)
            .environment(themeManager)
            .environment(lockManager)
            // Reading the theme here registers observation at the root, so a
            // theme change re-renders the whole tree with new accent colors.
            .tint(themeManager.current.accent)
            .overlay {
                if lockManager.isLocked {
                    LockScreenView(lockManager: lockManager)
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background, .inactive:
                    lockManager.lockIfEnabled()
                case .active:
                    if lockManager.isLocked {
                        Task { await lockManager.authenticate() }
                    }
                @unknown default:
                    break
                }
            }
            .task {
                // As early as possible, per RevenueCat's own guidance.
                PremiumManager.shared.configure()
                // Cold-launch lock: if the app-lock is enabled, require
                // authentication on first open too — not just after backgrounding.
                await lockManager.authenticateOnLaunchIfNeeded()
            }
        }
    }
}
