import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Speak freely.",
            body: "Sotto listens to everything you say — without you having to structure it or make it make sense.",
            accentColor: Color.sottoAccent // Terracotta
        ),
        OnboardingPage(
            title: "It notices things.",
            body: "Patterns in how you speak. Recurring themes. The emotions underneath the words you actually chose.",
            accentColor: Color(hex: "#EAB308") // Warm amber/sand
        ),
        OnboardingPage(
            title: "No performance.",
            body: "Sotto is not a productivity tool. No feeds, no scores to chase. Just a quiet place to be honest with yourself.",
            accentColor: Color(hex: "#64748B") // Slate/Sage
        )
    ]

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [
                    pages[currentPage].accentColor.opacity(0.08),
                    Color.sottoBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: currentPage)

            VStack(spacing: 0) {
                Spacer()

                // Page content
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        VStack(spacing: 28) {
                            VStack(spacing: 14) {
                                Text(page.title)
                                    .font(.largeTitle).fontWeight(.bold).fontDesign(.rounded)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.primary)

                                Text(page.body)
                                    .font(.body).fontDesign(.rounded)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(4)
                            }
                            .padding(.horizontal, 36)
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 400)

                Spacer()

                // Page indicator dots
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Capsule()
                            .fill(index == currentPage ? pages[currentPage].accentColor : Color.sottoTertiary)
                            .frame(width: index == currentPage ? 20 : 8, height: 8)
                            .animation(.spring(duration: 0.35), value: currentPage)
                    }
                }

                Spacer().frame(height: 40)

                // CTA button
                Button {
                    if currentPage < pages.count - 1 {
                        withAnimation { currentPage += 1 }
                    } else {
                        hasCompletedOnboarding = true
                    }
                } label: {
                    Text(currentPage < pages.count - 1 ? "Continue" : "Start journalling")
                        .font(.body).fontWeight(.semibold).fontDesign(.rounded)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            pages[currentPage].accentColor,
                            in: RoundedRectangle(cornerRadius: 16)
                        )
                        .animation(.easeInOut(duration: 0.3), value: currentPage)
                }
                .padding(.horizontal, 24)

                // Skip link
                if currentPage < pages.count - 1 {
                    Button {
                        hasCompletedOnboarding = true
                    } label: {
                        Text("Skip for now")
                            .font(.subheadline).fontDesign(.rounded)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 14)
                }

                Spacer().frame(height: 48)
            }
        }
    }
}

// MARK: - Page model
struct OnboardingPage {
    let title: String
    let body: String
    let accentColor: Color
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
}
