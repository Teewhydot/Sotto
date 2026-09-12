//  Shown when a free user tries to unlock Smart Insights. Mirrors the
//  WhisperSetupView/InsightModelSetupView visual language.
//

import SwiftUI
import RevenueCat

struct PremiumPaywallView: View {
    var onComplete: () -> Void

    @State private var premium = PremiumManager.shared
    @State private var purchasingPackageID: String?
    @State private var animatePulse = false
    @State private var showPrivacyPolicy = false

    /// Apple's standard EULA — App Review expects a reachable Terms of Use
    /// from any paywall. Replace only if you publish your own EULA.
    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#1D1E22"), Color(hex: "#2B2A2E"), Color(hex: "#1A1A1D")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        onComplete()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                ScrollView {
                    VStack(spacing: 0) {
                        Spacer().frame(height: 12)

                        // ── Icon ──────────────────────────────────────────
                        ZStack {
                            Circle()
                                .stroke(Color.sottoAccent.opacity(0.2), lineWidth: 1)
                                .frame(width: 130, height: 130)
                                .scaleEffect(animatePulse ? 1.15 : 1.0)
                                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: animatePulse)

                            Circle()
                                .fill(Color.sottoAccent.opacity(0.12))
                                .frame(width: 100, height: 100)

                            Image(systemName: "sparkles")
                                .font(.system(size: 52))
                                .foregroundStyle(Color.sottoAccent)
                        }
                        .padding(.bottom, 28)
                        .onAppear { animatePulse = true }

                        Text("Sotto Premium")
                            .font(.title2).fontWeight(.bold).fontDesign(.rounded)
                            .foregroundStyle(.white)

                        Text("Unlock Smart Insights — on-device AI that reflects on every entry, right on your phone.")
                            .font(.callout).fontDesign(.rounded)
                            .foregroundStyle(.white.opacity(0.65))
                            .multilineTextAlignment(.center)
                            .padding(.top, 10)
                            .padding(.horizontal, 32)

                        // ── Benefits ──────────────────────────────────────
                        VStack(alignment: .leading, spacing: 16) {
                            benefitRow(icon: "sparkles", text: "Emotion, themes & valence for every entry")
                            benefitRow(icon: "text.badge.checkmark", text: "Live transcript cleanup as you speak")
                            benefitRow(icon: "bubble.left.and.bubble.right", text: "A gentle follow-up question worth sitting with")
                            benefitRow(icon: "lock.shield", text: "Still 100% on-device — nothing you say ever leaves your phone")
                        }
                        .padding(.top, 32)
                        .padding(.horizontal, 32)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Spacer().frame(height: 32)

                        // ── Packages ──────────────────────────────────────
                        if premium.isLoadingOfferings {
                            ProgressView()
                                .tint(.white)
                                .padding(.vertical, 20)
                        } else if let packages = premium.currentOffering?.availablePackages, !packages.isEmpty {
                            VStack(spacing: 12) {
                                ForEach(packages, id: \.identifier) { package in
                                    packageButton(package)
                                }
                            }
                            .padding(.horizontal, 28)
                        } else {
                            Text(premium.offeringsError ?? "Offers aren't available right now — check back shortly.")
                                .font(.caption).fontDesign(.rounded)
                                .foregroundStyle(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }

                        if let error = premium.purchaseError {
                            Text(error)
                                .font(.caption).fontDesign(.rounded)
                                .foregroundStyle(.orange)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                                .padding(.top, 10)
                        }

                        Button {
                            Task { await premium.restorePurchases().report() }
                        } label: {
                            Text("Restore Purchases")
                                .font(.caption).fontWeight(.semibold).fontDesign(.rounded)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(.top, 18)

                        // Required disclosure (App Review 3.1.2): renewal
                        // terms and how to cancel, stated plainly before
                        // purchase rather than buried.
                        Text("Subscriptions renew automatically unless cancelled at least 24 hours before the period ends. Cancel anytime in your App Store account settings. Any unused portion of a free trial is forfeited when you purchase a subscription.")
                            .font(.caption2).fontDesign(.rounded)
                            .foregroundStyle(.white.opacity(0.35))
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                            .padding(.horizontal, 32)
                            .padding(.top, 20)

                        // App Review expects both of these reachable from
                        // any screen that sells a subscription.
                        HStack(spacing: 18) {
                            Link("Terms of Use", destination: termsURL)
                            Text("·").foregroundStyle(.white.opacity(0.25))
                            Button("Privacy Policy") { showPrivacyPolicy = true }
                        }
                        .font(.caption2).fontWeight(.semibold).fontDesign(.rounded)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 10)

                        Spacer().frame(height: 24)
                    }
                }
            }
        }
        .feedbackOverlay()
        .task { await premium.loadOfferings() }
        .onChange(of: premium.isSmartInsightsUnlocked) { _, unlocked in
            if unlocked { onComplete() }
        }
        // A sheet presented *from* a sheet is fine — the earlier
        // presentation bug was two sheet modifiers competing on one view,
        // not a chain like this.
        .sheet(isPresented: $showPrivacyPolicy) {
            NavigationStack { PrivacyPolicyView() }
        }
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(Color.sottoAccent)
                .frame(width: 20)
            Text(text)
                .font(.subheadline).fontDesign(.rounded)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func packageButton(_ package: Package) -> some View {
        Button {
            Task {
                purchasingPackageID = package.identifier
                await premium.purchase(package)
                purchasingPackageID = nil
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(periodLabel(for: package))
                            .font(.body).fontWeight(.semibold).fontDesign(.rounded)
                            .foregroundStyle(.white)
                        if let trial = Self.freeTrialLabel(for: package) {
                            Text(trial)
                                .font(.caption2).fontWeight(.bold).fontDesign(.rounded)
                                .foregroundStyle(Color(hex: "#1A1A1D"))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.sottoAccent, in: Capsule())
                        }
                        if let savings = savingsLabel(for: package) {
                            Text(savings)
                                .font(.caption2).fontWeight(.bold).fontDesign(.rounded)
                                .foregroundStyle(Color(hex: "#10B981"))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(hex: "#10B981").opacity(0.15), in: Capsule())
                        }
                    }
                    Text(Self.priceSubtitle(for: package))
                        .font(.caption).fontDesign(.rounded)
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                if purchasingPackageID == package.identifier {
                    ProgressView().tint(.white)
                } else {
                    Text(package.localizedPriceString)
                        .font(.body).fontWeight(.semibold).fontDesign(.rounded)
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.sottoAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.sottoAccent.opacity(0.4), lineWidth: 1)
            )
        }
        .disabled(purchasingPackageID != nil)
    }

    private func periodLabel(for package: Package) -> String {
        switch package.packageType {
        case .annual: "Yearly"
        case .sixMonth: "6 Months"
        case .threeMonth: "3 Months"
        case .twoMonth: "2 Months"
        case .monthly: "Monthly"
        case .weekly: "Weekly"
        case .lifetime: "Lifetime"
        default: package.storeProduct.localizedTitle
        }
    }

    /// "SAVE 17%" on the annual plan, computed from the real monthly price
    /// rather than hardcoded — a stale hardcoded number becomes a false
    /// advertised discount the moment either price changes.
    private func savingsLabel(for package: Package) -> String? {
        guard package.packageType == .annual,
              let monthly = premium.currentOffering?.availablePackages
                  .first(where: { $0.packageType == .monthly })
        else { return nil }

        let yearAtMonthlyRate = monthly.storeProduct.price * 12
        let annual = package.storeProduct.price
        guard yearAtMonthlyRate > 0, annual < yearAtMonthlyRate else { return nil }

        let ratio = (yearAtMonthlyRate - annual) / yearAtMonthlyRate
        let percent = Int((NSDecimalNumber(decimal: ratio).doubleValue * 100).rounded())
        guard percent > 0 else { return nil }
        return "SAVE \(percent)%"
    }

    // MARK: Trial + renewal disclosure
    // Read from the App Store product itself rather than hardcoded, so the
    // trial shown always matches what the user will actually be charged —
    // hardcoding it risks advertising a trial the product doesn't grant,
    // which is both a bad surprise and an App Review 3.1.2 problem.

    /// e.g. "1 WEEK FREE" — nil when the product has no free-trial offer.
    static func freeTrialLabel(for package: Package) -> String? {
        guard let intro = package.storeProduct.introductoryDiscount,
              intro.paymentMode == .freeTrial else { return nil }
        return "\(periodPhrase(intro.subscriptionPeriod).uppercased()) FREE"
    }

    /// e.g. "1 week free, then US$9.99/month"
    static func priceSubtitle(for package: Package) -> String {
        let unit = billingUnit(for: package)
        guard let intro = package.storeProduct.introductoryDiscount,
              intro.paymentMode == .freeTrial else {
            return "\(package.localizedPriceString)\(unit)"
        }
        return "\(periodPhrase(intro.subscriptionPeriod)) free, then \(package.localizedPriceString)\(unit)"
    }

    private static func billingUnit(for package: Package) -> String {
        guard let period = package.storeProduct.subscriptionPeriod else { return "" }
        switch period.unit {
        case .day: return "/day"
        case .week: return "/week"
        case .month: return "/month"
        case .year: return "/year"
        @unknown default: return ""
        }
    }

    /// "1 week", "2 weeks", "3 days" — pluralized from the store's own period.
    private static func periodPhrase(_ period: SubscriptionPeriod) -> String {
        let n = period.value
        let noun: String
        switch period.unit {
        case .day: noun = "day"
        case .week: noun = "week"
        case .month: noun = "month"
        case .year: noun = "year"
        @unknown default: noun = "period"
        }
        return "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}

#Preview {
    PremiumPaywallView(onComplete: {})
}
