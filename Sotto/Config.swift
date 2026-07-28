//  API keys are loaded from Info.plist at runtime.
//  The values are injected at build time via Secrets.xcconfig (gitignored).
//  See Secrets.xcconfig.template for the required keys.
//

import Foundation

enum Config {
    /// Gemini API key — injected from Secrets.xcconfig via Info.plist.
    /// Returns empty string if the key hasn't been configured.
    static var geminiAPIKey: String {
        Bundle.main.infoDictionary?["GeminiAPIKey"] as? String ?? ""
    }
}
