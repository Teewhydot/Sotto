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
                            Text("Offers aren't available right now — check back shortly.")
                                .font(.caption).fontDesign(.rounded)
                                .foregroundStyle(.white.opacity(0.5))
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
                            Task { await premium.restorePurchases() }
                        } label: {
                            Text("Restore Purchases")
                                .font(.caption).fontWeight(.semibold).fontDesign(.rounded)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(.top, 18)

                        Spacer().frame(height: 24)
                    }
                }
            }
        }
        .task { await premium.loadOfferings() }
        .onChange(of: premium.isSmartInsightsUnlocked) { _, unlocked in
            if unlocked { onComplete() }
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
                    Text(periodLabel(for: package))
                        .font(.body).fontWeight(.semibold).fontDesign(.rounded)
                        .foregroundStyle(.white)
                    Text(package.storeProduct.localizedTitle)
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
}

#Preview {
    PremiumPaywallView(onComplete: {})
}
