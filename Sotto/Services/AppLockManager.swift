import SwiftUI
import LocalAuthentication

// MARK: - App lock (Face ID / passcode)

@Observable
final class AppLockManager {
    var isLocked = false

    // Presenting the Face ID sheet itself bounces scenePhase through
    // .inactive and back to .active, which can re-trigger authenticate()
    // while the first evaluatePolicy call is still in flight. Two concurrent
    // LAContext requests racing LocalAuthenticationUIService's transition
    // animation is what crashes the system service, so a second call must
    // be a no-op rather than starting another evaluatePolicy.
    private var isAuthenticating = false

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "faceIDEnabled")
    }

    /// Cold launch with the lock enabled: show the lock screen immediately
    /// and prompt for authentication.
    func authenticateOnLaunchIfNeeded() async {
        guard isEnabled, !isLocked else { return }
        isLocked = true
        await authenticate()
    }

    /// Called when the app leaves the foreground.
    func lockIfEnabled() {
        guard isEnabled, !isLocked else { return }
        isLocked = true
    }

    /// Attempts biometric/passcode authentication to unlock.
    func authenticate() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        context.localizedReason = "Unlock your journal"

        // .deviceOwnerAuthentication falls back to the device passcode when
        // biometrics fail or are unavailable — never leaves the user stranded.
        let policy: LAPolicy = .deviceOwnerAuthentication
        var evalError: NSError?
        guard context.canEvaluatePolicy(policy, error: &evalError) else {
            // Only fail open when the device genuinely has no auth method
            // configured at all (no passcode set — the one case where this
            // policy can never succeed, e.g. a fresh simulator). Any other
            // reported reason is presumed transient/recoverable, so stay
            // locked and let the Unlock button retry rather than opening a
            // private journal on an unexplained LAContext failure.
            if (evalError as? LAError)?.code == .passcodeNotSet {
                isLocked = false
            }
            return
        }
        do {
            let success = try await context.evaluatePolicy(policy, localizedReason: context.localizedReason)
            isLocked = !success
        } catch {
            // User cancelled or too many failures — stay locked; they can retry.
        }
    }
}

// MARK: - Lock screen overlay

struct LockScreenView: View {
    /// Passed directly rather than via @Environment: the manager is created at
    /// the app root and this view renders from a root overlay, where an
    /// environment lookup failure is a fatal crash.
    var lockManager: AppLockManager

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.sottoAccent)
                Text("Sotto is locked")
                    .font(.title2).fontWeight(.semibold).fontDesign(.rounded)
                Text("Your journal stays private.")
                    .font(.subheadline).fontDesign(.rounded)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await lockManager.authenticate() }
                } label: {
                    Label("Unlock", systemImage: "faceid")
                        .font(.body.weight(.semibold)).fontDesign(.rounded)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 14)
                        .background(Color.sottoAccent, in: Capsule())
                }
                .padding(.top, 8)
                Spacer()
            }
        }
    }
}
