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
    private(set) var isConfigured = false

    private override init() {
        super.init()
    }

    /// Call once at launch, before anything checks entitlement. Safe to call
    /// repeatedly — only the first call does anything.
    func configure() {
        guard !isConfigured else { return }
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String,
              !apiKey.isEmpty, !apiKey.hasPrefix("appl_REPLACE") else {
            print("PremiumManager: no RevenueCat API key configured (see Secrets.xcconfig) — Smart Insights stays locked until one is added.")
            return
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
        defer { isLoadingOfferings = false }
        currentOffering = (try? await Purchases.shared.offerings())?.current
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

    /// Apple requires every paid-unlock flow to offer this — a reinstall or
    /// new device otherwise has no way back to an already-purchased
    /// entitlement.
    func restorePurchases() async {
        purchaseError = nil
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(info)
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    private func apply(_ info: CustomerInfo) {
        isSmartInsightsUnlocked = info.entitlements[Self.entitlementID]?.isActive == true
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
