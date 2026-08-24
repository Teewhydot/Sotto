import SwiftUI

// MARK: - In-app privacy policy
// Placeholder copy — replace the contact address and review wording before
// App Store submission.

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy Policy")
                    .font(.title2).fontWeight(.bold).fontDesign(.rounded)
                Text("Last updated: August 2026")
                    .font(.caption).foregroundStyle(.tertiary)

                section("Your entries stay on your device") {
                    "Every journal entry you write or speak is stored locally on this device using Apple's on-device storage. Sotto's servers do not exist — there is nothing to breach."
                }

                section("Voice transcription") {
                    "Voice entries are transcribed on-device. Your audio is never uploaded by us."
                }

                section("AI analysis") {
                    "To generate emotional insights, the text of an entry is sent to Google's Gemini API for processing. The transcript is used solely to produce that entry's analysis and is not retained for training by this app. If you prefer, you can decline analysis and save entries unanalysed."
                }

                section("No tracking") {
                    "Sotto contains no analytics, no advertising identifiers, and no third-party trackers."
                }

                section("You're in control") {
                    "Export all of your data as CSV from Settings at any time, or erase everything permanently with Delete All Data."
                }

                section("Contact") {
                    "Questions about privacy? Reach us at sotto@example.com."
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color.sottoBackground)
    }

    private func section(_ title: String, _ body: () -> String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline).fontDesign(.rounded)
            Text(body())
                .font(.subheadline).fontDesign(.rounded)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
    }
}

#Preview {
    NavigationStack { PrivacyPolicyView() }
}
