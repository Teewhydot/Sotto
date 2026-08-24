import SwiftUI

// MARK: - Main container
struct SottoMainView: View {
    @Environment(ThemeManager.self) private var themeManager
    @State private var selectedTab = 0
    @State private var showRecording = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Hide the system tab bar completely
            TabView(selection: $selectedTab) {
                TodayView(showRecording: $showRecording)
                    .tag(0)
                    .toolbar(.hidden, for: .tabBar)
                HistoryView()
                    .tag(1)
                    .toolbar(.hidden, for: .tabBar)
                InsightsView()
                    .tag(2)
                    .toolbar(.hidden, for: .tabBar)
            }

            // Custom bottom navigation bar
            SottoTabBar(selectedTab: $selectedTab, showRecording: $showRecording)
        }
        .fullScreenCover(isPresented: $showRecording) {
            RecordingView()
        }
        .ignoresSafeArea(.keyboard)
    }
}

// MARK: - Custom Tab Bar
struct SottoTabBar: View {
    @Binding var selectedTab: Int
    @Binding var showRecording: Bool

    var body: some View {
        HStack(spacing: 0) {
            TabBarButton(icon: "sun.max.fill", label: "Today",
                         isSelected: selectedTab == 0) {
                select(0)
            }

            TabBarButton(icon: "clock.arrow.circlepath", label: "History",
                         isSelected: selectedTab == 1) {
                select(1)
            }
            .padding(.leading, 18)

            Spacer()

            // Centre microphone button
            Button {
                Haptics.tap()
                showRecording = true
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    ThemeManager.shared.current.deep,
                                    ThemeManager.shared.current.accent.opacity(0.85)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 58, height: 58)
                        .shadow(color: Color.sottoAccent.opacity(0.45), radius: 10, y: 5)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .offset(y: -8)
            .accessibilityLabel("Start recording")

            Spacer()

            TabBarButton(icon: "chart.xyaxis.line", label: "Insights",
                         isSelected: selectedTab == 2) {
                select(2)
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func select(_ tab: Int) {
        Haptics.tap()
        selectedTab = tab
    }
}

// MARK: - Tab Bar Button
struct TabBarButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(label)
                    .font(.caption2).fontDesign(.rounded)
            }
            .foregroundStyle(isSelected ? Color.sottoAccent : .secondary)
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(.spring(duration: 0.25), value: isSelected)
        }
    }
}

#Preview {
    SottoMainView()
}
