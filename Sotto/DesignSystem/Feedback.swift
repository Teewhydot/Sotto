import SwiftUI

// MARK: - Message

/// One piece of transient feedback about an action the user just took.
///
/// Deliberately small: a headline, an optional detail line, and an optional
/// retry. Anything needing more than that wants a real screen (see
/// `ErrorSummaryView`), not a banner.
struct FeedbackMessage: Identifiable, Equatable {
    enum Style {
        /// The action completed. Auto-dismisses quickly.
        case success
        /// The action did not complete. Stays longer, and stays indefinitely
        /// when a retry is attached, since a banner the user never saw is the
        /// same as no feedback at all.
        case error
        /// Neither — the action completed, but not the way the user might
        /// assume (a degraded fallback, a skipped step).
        case info

        var icon: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .error: "exclamationmark.triangle.fill"
            case .info: "info.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .success: Color(hex: "#22C55E")
            case .error: Color(hex: "#EF4444")
            case .info: Color(hex: "#3B82F6")
            }
        }

        /// Seconds on screen before auto-dismissal. Errors get longer because
        /// they carry more to read and matter more to miss.
        var duration: Double {
            switch self {
            case .success: 2.2
            case .info: 3.5
            case .error: 5.0
            }
        }
    }

    let id = UUID()
    let style: Style
    let title: String
    var detail: String?
    /// Label shown on the trailing button. Nil means no button.
    var retryLabel: String?
    var retry: (@MainActor () -> Void)?

    /// Identity-based: the closure makes a structural comparison impossible,
    /// and a new message is always a new id anyway.
    static func == (lhs: FeedbackMessage, rhs: FeedbackMessage) -> Bool {
        lhs.id == rhs.id
    }

    /// What VoiceOver reads when the banner appears.
    var announcement: String {
        [title, detail].compactMap { $0 }.joined(separator: ". ")
    }
}

// MARK: - Centre

/// App-wide channel for "that worked" / "that didn't" .
///
/// Before this existed, every screen carried its own `@State` error string and
/// its own alert, so feedback was only present on the screens somebody
/// remembered to add it to, and success was never reported at all. One shared
/// centre means a new action gets feedback by calling one method, and haptics
/// stay in step with what is on screen automatically.
@MainActor
@Observable
final class FeedbackCenter {
    static let shared = FeedbackCenter()

    private(set) var message: FeedbackMessage?

    private var dismissTask: Task<Void, Never>?

    private init() {}

    // MARK: Posting

    func success(_ title: String, detail: String? = nil) {
        post(FeedbackMessage(style: .success, title: title, detail: detail))
    }

    func info(_ title: String, detail: String? = nil) {
        post(FeedbackMessage(style: .info, title: title, detail: detail))
    }

    func error(
        _ title: String,
        detail: String? = nil,
        retryLabel: String? = nil,
        retry: (@MainActor () -> Void)? = nil
    ) {
        post(
            FeedbackMessage(
                style: .error,
                title: title,
                detail: detail,
                retryLabel: retry == nil ? nil : (retryLabel ?? "Retry"),
                retry: retry
            )
        )
    }

    /// Convenience for a caught `Error`. The headline says what the user was
    /// trying to do — the underlying message alone ("The operation couldn't be
    /// completed") tells them nothing.
    func error(
        _ title: String,
        _ underlying: Error,
        retryLabel: String? = nil,
        retry: (@MainActor () -> Void)? = nil
    ) {
        error(
            title,
            detail: underlying.localizedDescription,
            retryLabel: retryLabel,
            retry: retry
        )
    }

    /// Shows `title` only once per process. For conditions that recur on every
    /// entry (a model that keeps falling back to heuristics) where repeating
    /// the notice every time would be nagging rather than informative.
    func infoOnce(_ key: String, _ title: String, detail: String? = nil) {
        guard shownOnceKeys.insert(key).inserted else { return }
        info(title, detail: detail)
    }

    private var shownOnceKeys: Set<String> = []

    // MARK: Dismissal

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation(.spring(duration: 0.28)) { message = nil }
    }

    private func post(_ new: FeedbackMessage) {
        dismissTask?.cancel()

        switch new.style {
        case .success: Haptics.success()
        case .error: Haptics.warning()
        case .info: Haptics.tap()
        }

        withAnimation(.spring(duration: 0.34, bounce: 0.18)) {
            message = new
        }

        // An error the user can act on stays until they act on it or dismiss
        // it; everything else clears itself.
        guard new.retry == nil else { return }

        let id = new.id
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(new.style.duration))
            guard !Task.isCancelled, self?.message?.id == id else { return }
            self?.dismiss()
        }
    }
}

// MARK: - Banner

private struct FeedbackBanner: View {
    let message: FeedbackMessage
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: message.style.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(message.style.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(message.title)
                    .font(.subheadline).fontWeight(.semibold).fontDesign(.rounded)
                    .foregroundStyle(.primary)

                if let detail = message.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption).fontDesign(.rounded)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let retry = message.retry, let label = message.retryLabel {
                Button {
                    onDismiss()
                    retry()
                } label: {
                    Text(label)
                        .font(.caption).fontWeight(.semibold).fontDesign(.rounded)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(message.style.tint, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(message.style.tint.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
        .padding(.horizontal, 16)
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Upward only — dragging down shouldn't tear it off the
                    // top of the screen.
                    dragOffset = min(0, value.translation.height)
                }
                .onEnded { value in
                    if value.translation.height < -20 {
                        onDismiss()
                    } else {
                        withAnimation(.spring(duration: 0.25)) { dragOffset = 0 }
                    }
                }
        )
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(message.announcement)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(named: "Dismiss", onDismiss)
    }
}

// MARK: - Overlay modifier

/// Hosts the banner above whatever it is applied to.
///
/// Apply this at the app root **and** at the root of every full-screen cover
/// or sheet: presented content sits in its own hosting layer, so an overlay
/// only on the root window would be covered by it. Rendering the same message
/// in more than one place is harmless — only the topmost one is visible.
private struct FeedbackOverlayModifier: ViewModifier {
    @State private var center = FeedbackCenter.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message = center.message {
                    FeedbackBanner(message: message) { center.dismiss() }
                        .transition(
                            .move(edge: .top).combined(with: .opacity)
                        )
                        .zIndex(100)
                }
            }
            // The banner reports an action's outcome; it must never be
            // pushed around by the keyboard that action was typed into.
            .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

extension View {
    /// Displays app-level success/error feedback over this view.
    func feedbackOverlay() -> some View {
        modifier(FeedbackOverlayModifier())
    }
}

#Preview {
    VStack(spacing: 12) {
        Button("Success") { FeedbackCenter.shared.success("Entry saved") }
        Button("Error") {
            FeedbackCenter.shared.error(
                "Couldn't save entry",
                detail: "The database is unavailable.",
                retry: {}
            )
        }
        Button("Info") {
            FeedbackCenter.shared.info(
                "Used simpler insights",
                detail: "The on-device model wasn't reachable."
            )
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .feedbackOverlay()
}
