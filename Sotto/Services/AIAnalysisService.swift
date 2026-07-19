//
//  AIAnalysisService.swift
//  Sotto
//

import Foundation
import GoogleGenerativeAI
import SwiftUI

struct AnalysisResult: Codable, Equatable {
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
        guard Config.geminiAPIKey != "YOUR_GEMINI_API_KEY_HERE" else {
            return nil
        }
        return GenerativeModel(
            name: "gemini-1.5-pro",
            apiKey: Config.geminiAPIKey,
            generationConfig: GenerationConfig(responseMIMEType: "application/json")
        )
    }
    
    func analyzeTranscript(_ text: String) async {
        state = .loading
        
        guard let model = model else {
            state = .error(.aiAnalysisFailed("Gemini API key is missing. Please add it to Config.swift."))
            return
        }
        
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .error(.aiAnalysisFailed("Transcript is empty."))
            return
        }

        let prefix = String(Config.geminiAPIKey.prefix(10))
        print("Using Gemini API Key starting with: \(prefix)...")
        if prefix.hasPrefix("AQ.") {
            state = .error(.aiAnalysisFailed("Invalid API Key format. Gemini keys must start with 'AIza'. You are using an old or incorrect key format starting with 'AQ.'. Please generate a new key at aistudio.google.com/app/apikey and update Secrets.xcconfig."))
            return
        }
        
        let prompt = """
        Analyze the following journal entry transcript and return a JSON object containing psychological insights.
        The JSON must strictly match this structure:
        {
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
                  let data = responseText.data(using: .utf8) else {
                throw AppError.aiAnalysisFailed("Invalid or empty response from Gemini.")
            }
            
            let result = try JSONDecoder().decode(AnalysisResult.self, from: data)
            state = .loaded(result)
        } catch {
            state = .error(.aiAnalysisFailed(error.localizedDescription))
        }
    }
}
