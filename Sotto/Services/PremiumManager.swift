import Foundation
import RevenueCat

/// Gates Smart Insights behind a RevenueCat-managed subscription. Everything
/// else in Sotto — recording, transcription, history, export, delete-all —
/// stays free; this is the one place billing enters the app.
///
/// `entitlementID` below must match the identifier configured in the
/// RevenueCat dashboard's Entitlements tab.
@MainActor
@Observable
final class PremiumManager: NSObject {
    static let shared = PremiumManager()

    private static let entitlementID = "smart_insights"

    private(set) var isSmartInsightsUnlocked = false
    private(set) var isLoadingOfferings = false
    private(set) var currentOffering: Offering?
    private(set) var purchaseError: String?
    private(set) var offeringsError: String?
    private(set) var isConfigured = false

    /// Full entitlement record for the active subscription, so the
    /// subscription screen can show real renewal/trial state instead of
    /// just a locked/unlocked boolean.
    private(set) var activeEntitlement: EntitlementInfo?

    private override init() {
        super.init()
    }

    /// Call once at launch, before anything checks entitlement. Safe to call
    /// repeatedly — only the first call does anything.
    func configure() {
        guard !isConfigured else { return }
        let rawValue = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String
        guard let apiKey = rawValue, !apiKey.isEmpty, !apiKey.hasPrefix("appl_REPLACE") else {
            // If you've already edited Secrets.xcconfig and still see this,
            // it's almost always a stale build — INFOPLIST_KEY_* values are
            // baked in at build time, so a plain re-run without a rebuild
            // (or a run from a different DerivedData / target) keeps
            // whatever key was embedded last. Product ▸ Clean Build Folder,
            // then rebuild. `rawValue` printed below shows exactly what this
            // build actually embedded, to tell that apart from "key missing."
            print("PremiumManager: no usable RevenueCat API key (read: \(rawValue.map { "\"\($0.prefix(12))…\"" } ?? "nil")) — Smart Insights stays locked. Check Secrets.xcconfig, then Clean Build Folder if you've already set it.")
            return
        }
        // Test Store keys simulate purchases, never touch StoreKit, earn
        // nothing, and get the app rejected at review. Failing the build's
        // launch is the only feedback loud enough to not be shipped past.
        if apiKey.hasPrefix("test_") {
            #if DEBUG
            print("PremiumManager: RevenueCat Test Store key in use — purchases are simulated and entitlements are fake. Swap REVENUECAT_API_KEY in Secrets.xcconfig for the production `appl_` key before archiving.")
            #else
            fatalError("A RevenueCat Test Store API key is embedded in a Release build. Set REVENUECAT_API_KEY in Secrets.xcconfig to the production `appl_` key.")
            #endif
        }

        #if DEBUG
        Purchases.logLevel = .warn
        #endif
        Purchases.configure(withAPIKey: apiKey)
        Purchases.shared.delegate = self
        isConfigured = true
        Task { await refreshEntitlement() }
    }

    /// Re-checks entitlement against RevenueCat's cached customer info.
    /// Cheap and safe to call whenever a screen that cares about
    /// entitlement (Settings, the setup screen) appears.
    func refreshEntitlement() async {
        guard isConfigured, let info = try? await Purchases.shared.customerInfo() else { return }
        apply(info)
    }

    func loadOfferings() async {
        guard isConfigured else { return }
        isLoadingOfferings = true
        offeringsError = nil
        defer { isLoadingOfferings = false }
        do {
            let offerings = try await Purchases.shared.offerings()
            currentOffering = offerings.current
            if currentOffering == nil {
                // Reachable RevenueCat, but no Offering marked "current" (or
                // it has no packages) — a dashboard configuration gap, not a
                // network/SDK problem. Swallowing this via `try?` used to
                // just show a generic "unavailable" with no way to tell
                // the two apart.
                offeringsError = "No current offering is configured in RevenueCat yet — add packages to an Offering and mark it current."
            }
        } catch {
            offeringsError = error.localizedDescription
            print("PremiumManager: failed to load offerings — \(error)")
        }
    }

    func purchase(_ package: Package) async {
        purchaseError = nil
        do {
            let result = try await Purchases.shared.purchase(package: package)
            apply(result.customerInfo)
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    /// What a restore actually did. "Succeeded" and "found nothing" are
    /// different outcomes and the user needs to be able to tell them apart —
    /// a restore that silently finds no purchase is indistinguishable from a
    /// button that does nothing.
    enum RestoreOutcome {
        case unlocked
        case nothingToRestore
        case failed(String)

        /// Reports itself through the app-level feedback banner.
        @MainActor
        func report() {
            switch self {
            case .unlocked:
                FeedbackCenter.shared.success(
                    "Purchases restored",
                    detail: "Smart Insights is unlocked on this device."
                )
            case .nothingToRestore:
                FeedbackCenter.shared.info(
                    "Nothing to restore",
                    detail: "No previous Sotto subscription was found for this Apple Account."
                )
            case .failed(let message):
                FeedbackCenter.shared.error("Couldn't restore purchases", detail: message)
            }
        }
    }

    /// Apple requires every paid-unlock flow to offer this — a reinstall or
    /// new device otherwise has no way back to an already-purchased
    /// entitlement.
    @discardableResult
    func restorePurchases() async -> RestoreOutcome {
        purchaseError = nil
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(info)
            return isSmartInsightsUnlocked ? .unlocked : .nothingToRestore
        } catch {
            purchaseError = error.localizedDescription
            return .failed(error.localizedDescription)
        }
    }

    private func apply(_ info: CustomerInfo) {
        // `entitlements[id]` also returns lapsed entitlements, and the SDK
        // logs "Entitlement is no longer active (expired ...)" on every read
        // of one — which is where the repeated warnings in the console came
        // from. `.active` is the lookup that matches what this app means by
        // entitled, and it keeps a lapsed subscription out of
        // `activeEntitlement`, which `activePlanName` reads without checking
        // `isActive` (so an expired yearly plan still displayed as "Yearly").
        let entitlement = info.entitlements.active[Self.entitlementID]
        isSmartInsightsUnlocked = entitlement != nil
        activeEntitlement = entitlement
        syncTrialReminder()
    }

    /// Keeps the local "your trial ends soon" reminder in step with the
    /// real entitlement — scheduled while in trial, cleared the moment the
    /// user converts or cancels so nobody gets a warning about a charge
    /// that isn't coming.
    private func syncTrialReminder() {
        guard case .trial(let endsOn) = subscriptionStatus, let endsOn else {
            NotificationManager.shared.cancelTrialEndingReminder()
            return
        }
        let price = currentOffering?.availablePackages
            .first { $0.storeProduct.productIdentifier == activeEntitlement?.productIdentifier }?
            .localizedPriceString
        Task {
            await NotificationManager.shared.scheduleTrialEndingReminder(
                trialEnds: endsOn,
                priceDescription: price ?? "the subscription price"
            )
        }
    }

    /// Opens Apple's own manage-subscriptions sheet. Apple requires a
    /// reachable cancellation path, and routing to the system sheet is both
    /// the compliant option and the one users already recognize — we never
    /// try to intercept or discourage the cancel.
    func openManageSubscriptions() async {
        purchaseError = nil
        do {
            try await Purchases.shared.showManageSubscriptions()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: Subscription status (for the management screen)

    enum SubscriptionStatus {
        case none
        case trial(endsOn: Date?)
        case active(renewsOn: Date?)
        case cancelling(accessUntil: Date?)
        case billingIssue(retryUntil: Date?)
    }

    var subscriptionStatus: SubscriptionStatus {
        // `activeEntitlement` is only ever set from `entitlements.active`,
        // so reaching here means the subscription is live.
        guard let entitlement = activeEntitlement else { return .none }
        if entitlement.billingIssueDetectedAt != nil {
            return .billingIssue(retryUntil: entitlement.expirationDate)
        }
        if entitlement.periodType == .trial {
            return .trial(endsOn: entitlement.expirationDate)
        }
        if !entitlement.willRenew {
            return .cancelling(accessUntil: entitlement.expirationDate)
        }
        return .active(renewsOn: entitlement.expirationDate)
    }

    /// Human-readable plan name derived from the purchased product.
    var activePlanName: String? {
        guard let id = activeEntitlement?.productIdentifier else { return nil }
        if id.localizedCaseInsensitiveContains("annual") || id.localizedCaseInsensitiveContains("year") {
            return "Yearly"
        }
        if id.localizedCaseInsensitiveContains("month") {
            return "Monthly"
        }
        return nil
    }
}

extension PremiumManager: PurchasesDelegate {
    /// RevenueCat delivers this from its own internal dispatch, not
    /// necessarily the main thread — hop explicitly rather than rely on
    /// implicit isolation across an @objc delegate boundary.
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in self.apply(customerInfo) }
    }
}
