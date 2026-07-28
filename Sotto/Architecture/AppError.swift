import Foundation

enum AppError: Error, LocalizedError, Equatable {
    case initializationFailed(String)
    case micPermissionDenied
    case speechRecognitionFailed(String)
    case modelDownloadFailed(String)
    case aiAnalysisFailed(String)
    case databaseError(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .initializationFailed(let msg): return "Initialization failed: \(msg)"
        case .micPermissionDenied: return "Microphone permission was denied. Please enable it in Settings."
        case .speechRecognitionFailed(let msg): return "Transcription failed: \(msg)"
        case .modelDownloadFailed(let msg): return "Failed to download model: \(msg)"
        case .aiAnalysisFailed(let msg): return "AI Analysis failed: \(msg)"
        case .databaseError(let msg): return "Database error: \(msg)"
        case .unknown(let msg): return "An unknown error occurred: \(msg)"
        }
    }
}
