import SwiftUI
import LocalAuthentication

// MARK: - App lock (Face ID / passcode)

@Observable
final class AppLockManager {
    var isLocked = false

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
        guard isLocked else { return }
        let context = LAContext()
        context.localizedReason = "Unlock your journal"

        // .deviceOwnerAuthentication falls back to the device passcode when
        // biometrics fail or are unavailable — never leaves the user stranded.
        let policy: LAPolicy = .deviceOwnerAuthentication
        guard context.canEvaluatePolicy(policy, error: nil) else {
            // No auth method available (e.g. simulator without enrolled
            // biometrics and no passcode) — fail open rather than brick the app.
            isLocked = false
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
    @Environment(AppLockManager.self) private var lockManager

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
