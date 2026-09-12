import Foundation
import NaturalLanguage

// MARK: - Deterministic on-device fallback
/// Produces insights with Apple's NaturalLanguage framework and lexicon rules.
/// No LLM involved: instant, works on every device, fully offline. Quality is
/// shallower than the local model — this exists so analysis never fails while
/// the LLM downloads (or if it errors).
enum NLInsightEngine {

    static func analyze(transcript: String) -> AnalysisResult {
        let lower = transcript.lowercased()
        let valence = sentiment(for: transcript)
        let emotion = primaryEmotion(lower: lower, valence: valence)
        let themes = extractThemes(from: transcript)

        return AnalysisResult(
            summary: summarize(transcript),
            primaryEmotion: emotion,
            intensity: intensity(lower: lower, valence: valence),
            energyLevel: energy(lower: lower),
            valence: valence,
            themes: themes,
            // Deliberately empty. This engine has no model behind it, and a
            // canned question picked by `transcript.count % 3` is not a
            // reflection on the entry — it only looks like one. The screens
            // that show it hide the section when it is blank, which is the
            // honest result: no question rather than a fake one.
            followUpQuestion: "",
            // Empty for the same reason as the question above. Interpolating
            // a theme into "You didn't say it outright, but the way you talked
            // about \(theme)..." produces a sentence that claims to have
            // noticed something unsaid, when all it did was substitute a
            // keyword into one of five templates. Reading an entry between the
            // lines needs a model.
            hiddenObservation: ""
        )
    }

    // MARK: Sentiment

    private static func sentiment(for text: String) -> Double {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        guard let raw = tag?.rawValue, let score = Double(raw) else { return 0 }
        return max(-1.0, min(1.0, score))
    }

    // MARK: Emotion

    private static let emotionLexicons: [(emotion: String, words: Set<String>)] = [
        ("Anxious", ["anxious", "worried", "nervous", "stressed", "stress", "afraid", "scared", "overwhelmed", "panic", "dread", "uneasy"]),
        ("Sad", ["sad", "down", "lonely", "hurt", "depressed", "cry", "crying", "empty", "grief", "miss"]),
        ("Frustrated", ["angry", "mad", "frustrated", "annoyed", "furious", "unfair", "irritated", "fed up"]),
        ("Joyful", ["happy", "excited", "grateful", "thankful", "joy", "love", "amazing", "wonderful", "delighted", "thrilled"]),
        ("Peaceful", ["calm", "peaceful", "relaxed", "content", "quiet", "rested", "gentle", "still"]),
    ]

    private static func primaryEmotion(lower: String, valence: Double) -> String {
        var best: (emotion: String, count: Int)?
        for lexicon in emotionLexicons {
            let count = lexicon.words.reduce(0) { $0 + (lower.contains($1) ? 1 : 0) }
            if count > 0, count > (best?.count ?? 0) {
                best = (lexicon.emotion, count)
            }
        }
        if let best { return best.emotion }
        if valence > 0.15 { return "Hopeful" }
        if valence < -0.15 { return "Heavy" }
        return "Reflective"
    }

    // MARK: Scales

    private static let intensifiers = ["so ", "really ", "extremely ", "incredibly ", "can't believe", "unbelievable", "exhausted", "overwhelming"]

    private static func intensity(lower: String, valence: Double) -> Int {
        var score = 5.0 + abs(valence) * 3.0
        score += min(Double(lower.filter { $0 == "!" }.count), 3) * 0.5
        score += intensifiers.reduce(0) { $0 + (lower.contains($1) ? 1 : 0) } * 0.7
        return clamp(score.rounded(), 1, 10)
    }

    private static let actionWords = ["went", "did", "started", "finished", "ran", "walked", "worked", "met", "called", "planned", "built", "cleaned", "traveled", "cooked", "trained"]

    private static func energy(lower: String) -> Int {
        var score = 4.5
        score += Double(actionWords.reduce(0) { $0 + (lower.contains($1) ? 1 : 0) }) * 0.8
        score += min(Double(lower.filter { $0 == "!" }.count), 4) * 0.4
        if lower.contains("tired") || lower.contains("drained") || lower.contains("exhausted") { score -= 2 }
        return clamp(score.rounded(), 1, 10)
    }

    // MARK: Themes

    private static let themeStopWords: Set<String> = [
        "today", "yesterday", "thing", "things", "stuff", "lot", "way", "time", "day", "days", "week", "morning", "night", "people", "something", "anything", "everyone", "really", "just", "feel", "felt", "feeling", "know", "think", "thought", "thoughts", "want", "need",
    ]

    private static func extractThemes(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        var frequencies: [String: Int] = [:]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, _ in
            if tag == .noun, let token = tag?.rawValue.lowercased() {
                frequencies[token, default: 0] += 1
            }
            return true
        }

        let ranked = frequencies
            .filter { $0.key.count > 2 && !themeStopWords.contains($0.key) }
            .sorted { ($0.value, $0.key) > ($1.value, $1.key) }
            .map(\.key)

        var themes = Array(ranked.prefix(3))
        for filler in ["life", "work", "self"] where themes.count < 3 {
            themes.append(filler)
        }
        return themes
    }

    // MARK: Generative-ish text


    private static func summarize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentences = trimmed.split(whereSeparator: { ".!?".contains($0) })
        let first = sentences.prefix(2).joined(separator: ". ").trimmingCharacters(in: .whitespaces)
        if first.isEmpty { return trimmed }
        let summary = first.hasSuffix(".") ? first : first + "."
        return summary.count > 160 ? String(summary.prefix(157)) + "…" : summary
    }

    // MARK: Light cleanup (deterministic dictation polish)

    /// Fast heuristic cleanup used when the local LLM isn't loaded: strips
    /// clear filler sounds, collapses stutters/duplicated words, fixes
    /// punctuation spacing, capitalizes sentences, and tidies blank lines.
    /// Conservative on purpose — ambiguous fillers ("like", "I mean") are
    /// left for the LLM path.
    static func lightCleanup(_ text: String) -> String {
        var out = text

        // Clear filler sounds at word boundaries, swallowing an adjacent comma.
        out = out.replacingOccurrences(
            of: "\\b(?:um+|uh+|erm+|err+|ah+|hmm+|mmm+|mm-hmm)\\b[,.]?",
            with: "", options: [.regularExpression, .caseInsensitive]
        )

        // Immediate duplicated words ("I I", "the the") → single.
        out = out.replacingOccurrences(
            of: "\\b(\\w+)( \\1\\b)+",
            with: "$1", options: [.regularExpression, .caseInsensitive]
        )

        // Punctuation hygiene.
        out = out.replacingOccurrences(of: "\\s+([,.;:!?])", with: "$1", options: .regularExpression)
        out = out.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)

        // Sentence capitalization.
        out = capitalizeSentences(out)

        // Terminal punctuation.
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = trimmed.last, last.isLetter || last.isNumber {
            out = trimmed + "."
        } else {
            out = trimmed
        }

        // Collapse runs of blank lines.
        out = out.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)

        return out
    }

    private static func capitalizeSentences(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "(^|[.!?]\\s*)([a-z])") else {
            return text
        }
        let nsText = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            let prefixRange = match.range(at: 1)
            let letterRange = match.range(at: 2)
            result += nsText.substring(with: NSRange(location: cursor, length: prefixRange.location - cursor))
            result += prefixRange.length > 0 ? nsText.substring(with: prefixRange) : ""
            let letter = nsText.substring(with: letterRange)
            result += letter.uppercased()
            cursor = letterRange.location + letterRange.length
        }
        result += nsText.substring(from: cursor)
        return result
    }

    private static func clamp(_ value: Double, _ low: Int, _ high: Int) -> Int {
        Int(max(Double(low), min(Double(high), value)))
    }
}
