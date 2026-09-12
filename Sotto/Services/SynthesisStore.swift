import Foundation

/// Caches synthesis results for the lifetime of the process.
///
/// A synthesis costs several seconds of on-device generation, and the Insights
/// screen is somewhere people arrive, leave and come back to. Without this,
/// switching period and switching back would regenerate from scratch and the
/// wording would change slightly each time — which makes a considered
/// observation look like a slot machine.
///
/// The cache key is a fingerprint of the exact entries that went in, so adding
/// an entry or editing one invalidates it, and nothing else does.
@MainActor
@Observable
final class SynthesisStore {
    static let shared = SynthesisStore()

    private init() {}

    enum State: Equatable {
        case idle
        case generating
        case ready(JournalSynthesis)
        /// Ran, but there was not enough to say. Distinct from `idle` so the
        /// UI can explain rather than showing a permanent spinner.
        case notEnoughYet
    }

    private var cache: [String: JournalSynthesis] = [:]
    private var inFlight: [String: Task<Void, Never>] = [:]
    private(set) var states: [String: State] = [:]

    func state(for key: String) -> State {
        if let cached = cache[key] { return .ready(cached) }
        return states[key] ?? .idle
    }

    /// Starts generation unless it is already done or already running.
    func generate(key: String, entries: [SynthesisEntry], periodLabel: String) {
        guard cache[key] == nil, inFlight[key] == nil else { return }
        if states[key] == .notEnoughYet { return }

        states[key] = .generating
        inFlight[key] = Task { [weak self] in
            let result = await InsightEngines.shared.synthesise(
                entries: entries,
                periodLabel: periodLabel
            )
            guard let self, !Task.isCancelled else { return }
            if let result, !result.patterns.isEmpty {
                self.cache[key] = result
                self.states[key] = .ready(result)
            } else {
                self.states[key] = .notEnoughYet
            }
            self.inFlight[key] = nil
        }
    }

    /// Drops everything. Called when the entitlement is lost, so a lapsed
    /// subscriber does not keep reading a cached premium synthesis.
    func clear() {
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        cache.removeAll()
        states.removeAll()
    }

    /// A stable identity for "these exact entries, in this period".
    ///
    /// Includes each entry's own signals, not just its id, so re-analysing an
    /// entry (which rewrites its themes and valence) produces a new key and a
    /// fresh synthesis.
    nonisolated static func fingerprint(periodLabel: String, entries: [SynthesisEntry]) -> String {
        var hasher = Hasher()
        hasher.combine(periodLabel)
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            hasher.combine(entry.id)
            hasher.combine(entry.valence)
            hasher.combine(entry.primaryEmotion)
            hasher.combine(entry.themes)
        }
        return "\(periodLabel)-\(hasher.finalize())"
    }
}
