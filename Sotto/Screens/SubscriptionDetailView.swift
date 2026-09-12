//  Replaces RevenueCat's prebuilt Customer Center. That screen surfaces
//  internal plumbing (raw app user IDs, store metadata) that means nothing
//  to a person; this answers the three questions someone actually opens a
//  subscription screen to ask: what am I on, when am I next charged, and
//  how do I change or stop it.
//

import SwiftUI
import RevenueCat

struct SubscriptionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var premium = PremiumManager.shared
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            List {
                statusSection
                benefitsSection
                manageSection
            }
            .navigationTitle("Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .feedbackOverlay()
            .task { await premium.refreshEntitlement() }
        }
    }

    // MARK: Status

    private var statusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: statusIcon)
                        .font(.title3)
                        .foregroundStyle(statusColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(planTitle)
                            .font(.headline).fontDesign(.rounded)
                        Text(statusHeadline)
                            .font(.subheadline)
                            .foregroundStyle(statusColor)
                    }
                }

                if let detail = statusDetail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var planTitle: String {
        if let name = premium.activePlanName { return "Sotto Premium · \(name)" }
        return premium.isSmartInsightsUnlocked ? "Sotto Premium" : "Sotto Free"
    }

    private var statusIcon: String {
        switch premium.subscriptionStatus {
        case .none: "circle.dashed"
        case .trial: "gift.fill"
        case .active: "checkmark.circle.fill"
        case .cancelling: "clock.badge.exclamationmark"
        case .billingIssue: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch premium.subscriptionStatus {
        case .none: .secondary
        case .trial: Color.sottoAccent
        case .active: Color(hex: "#10B981")
        case .cancelling: Color(hex: "#F59E0B")
        case .billingIssue: Color(hex: "#EF4444")
        }
    }

    private var statusHeadline: String {
        switch premium.subscriptionStatus {
        case .none:
            return "Not subscribed"
        case .trial(let endsOn):
            guard let endsOn else { return "Free trial" }
            let days = daysRemaining(until: endsOn)
            return days <= 0 ? "Free trial ends today" : "Free trial · \(days) day\(days == 1 ? "" : "s") left"
        case .active(let renewsOn):
            guard let renewsOn else { return "Active" }
            return "Renews \(Self.dateFormatter.string(from: renewsOn))"
        case .cancelling(let accessUntil):
            guard let accessUntil else { return "Cancelled" }
            return "Ends \(Self.dateFormatter.string(from: accessUntil))"
        case .billingIssue:
            return "Payment problem"
        }
    }

    private var statusDetail: String? {
        switch premium.subscriptionStatus {
        case .none:
            return "Smart Insights uses the simpler on-device analysis. Everything else in Sotto is unchanged."
        case .trial(let endsOn):
            guard let endsOn else { return nil }
            return "You won't be charged until \(Self.dateFormatter.string(from: endsOn)). Cancel any time before then and you won't pay anything."
        case .active:
            return "Thanks for supporting Sotto. Your entries never leave this device — a subscription doesn't change that."
        case .cancelling(let accessUntil):
            guard let accessUntil else { return nil }
            return "You keep Smart Insights until \(Self.dateFormatter.string(from: accessUntil)). After that, entries fall back to the simpler on-device analysis — nothing you've already written is lost or hidden."
        case .billingIssue:
            return "The App Store couldn't process your last payment. Updating your payment method in App Store settings usually fixes it — you keep access while Apple retries."
        }
    }

    private func daysRemaining(until date: Date) -> Int {
        let days = Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0
        return max(0, days)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    // MARK: What it includes

    private var benefitsSection: some View {
        Section("What Premium includes") {
            benefitRow("sparkles", "Smart Insights", "Emotion, themes and valence written by the on-device model")
            benefitRow("text.badge.checkmark", "Live cleanup", "Filler words and false starts removed as you speak")
            benefitRow("bubble.left.and.bubble.right", "Follow-up questions", "A reflective prompt after each entry")
            benefitRow("lock.shield", "Still fully on-device", "Subscribing adds nothing to the network — analysis stays local")
        }
    }

    private func benefitRow(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(Color.sottoAccent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.medium)
                Text(subtitle)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Manage

    private var manageSection: some View {
        Section {
            Button {
                Task {
                    isWorking = true
                    await premium.openManageSubscriptions()
                    isWorking = false
                }
            } label: {
                HStack {
                    Label(manageLabel, systemImage: "creditcard")
                    Spacer()
                    if isWorking {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            .disabled(isWorking)

            Button {
                Task {
                    isWorking = true
                    let outcome = await premium.restorePurchases()
                    isWorking = false
                    outcome.report()
                }
            } label: {
                Label("Restore Purchases", systemImage: "arrow.clockwise")
            }
            .disabled(isWorking)
        } footer: {
            if let error = premium.purchaseError {
                Text(error).foregroundStyle(.orange)
            } else {
                Text("Changing or cancelling a subscription happens in your App Store account — Sotto can't do it for you, and won't try to talk you out of it.")
            }
        }
    }

    /// Cancelling and changing plan are the same App Store destination;
    /// naming it for what the user most likely wants avoids making them
    /// hunt for a "cancel" that looks deliberately hidden.
    private var manageLabel: String {
        switch premium.subscriptionStatus {
        case .none: "Manage in App Store"
        case .cancelling: "Resubscribe in App Store"
        default: "Change or cancel plan"
        }
    }
}

#Preview {
    SubscriptionDetailView()
}
