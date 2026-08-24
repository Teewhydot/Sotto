import Foundation
import GoogleGenerativeAI
import SwiftUI

struct AnalysisResult: Codable, Equatable {
    let summary: String
    let primaryEmotion: String
    let intensity: Int
    let energyLevel: Int
    let valence: Double
    let themes: [String]
    let followUpQuestion: String
    let hiddenObservation: String
}

@Observable
final class AIAnalysisService {
    var state: ViewState<AnalysisResult> = .initial

    private var model: GenerativeModel? {
        guard !Config.geminiAPIKey.isEmpty,
              Config.geminiAPIKey != "YOUR_GEMINI_API_KEY_HERE" else {
            return nil
        }
        return GenerativeModel(
            name: "gemini-2.5-flash",
            apiKey: Config.geminiAPIKey,
            generationConfig: GenerationConfig(responseMIMEType: "application/json")
        )
    }

    func analyzeTranscript(_ text: String) async {
        state = .loading

        // Validate input before configuration so user-facing errors are
        // deterministic regardless of API key state.
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .error(.aiAnalysisFailed("Transcript is empty."))
            return
        }

        guard let model = model else {
            state = .error(.aiAnalysisFailed("Gemini API key is missing. Add GEMINI_API_KEY to Secrets.xcconfig (see Secrets.xcconfig.template)."))
            return
        }

        // "AQ."-prefixed values are not Gemini API keys (commonly pasted from
        // the wrong console page). Catch it early with an actionable message.
        if Config.geminiAPIKey.hasPrefix("AQ.") {
            state = .error(.aiAnalysisFailed(
                "The configured API key is not a valid Gemini key. Generate a new one at aistudio.google.com/app/apikey (keys start with \"AIza\") and update GEMINI_API_KEY in Secrets.xcconfig."
            ))
            return
        }

        let prompt = """
        Analyze the following journal entry transcript and return a JSON object containing psychological insights.
        The JSON must strictly match this structure:
        {
          "summary": "String (A concise 1-2 sentence neutral summary of what the entry is about)",
          "primaryEmotion": "String (e.g. Reflective, Anxious, Joyful)",
          "intensity": Int (1 to 10),
          "energyLevel": Int (1 to 10),
          "valence": Double (-1.0 for very negative, 1.0 for very positive),
          "themes": ["String", "String", "String"],
          "followUpQuestion": "String (A thoughtful question to prompt further reflection)",
          "hiddenObservation": "String (A deep, subtextual observation about the user's state)"
        }

        Transcript: "\(text)"
        """

        do {
            let response = try await model.generateContent(prompt)
            guard let responseText = response.text,
                  let data = Self.cleanedJSONData(from: responseText) else {
                throw AppError.aiAnalysisFailed("Invalid or empty response from Gemini.")
            }

            let result = try JSONDecoder().decode(AnalysisResult.self, from: data)
            state = .loaded(result)
        } catch {
            state = .error(.aiAnalysisFailed(error.localizedDescription))
        }
    }

    /// Tolerates models wrapping JSON in markdown fences.
    static func cleanedJSONData(from text: String) -> Data? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            trimmed = String(trimmed.dropFirst(3))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("json") { trimmed = String(trimmed.dropFirst(4)) }
            if trimmed.hasSuffix("```") { trimmed = String(trimmed.dropLast(3)) }
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed.data(using: .utf8)
    }
}
