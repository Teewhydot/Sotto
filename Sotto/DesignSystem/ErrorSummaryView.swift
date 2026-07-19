//
//  ErrorSummaryView.swift
//  Sotto
//

import SwiftUI

struct ErrorSummaryView: View {
    let error: AppError
    let retryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 42))
                .foregroundStyle(Color(hex: "#EF4444"))

            VStack(spacing: 8) {
                Text("Something went wrong")
                    .font(.title3).fontWeight(.semibold).fontDesign(.rounded)
                
                Text(error.localizedDescription)
                    .font(.body).fontDesign(.rounded)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if let retryAction {
                Button(action: retryAction) {
                    Text("Try Again")
                        .font(.subheadline).fontWeight(.semibold)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.sottoAccent, in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ErrorSummaryView(error: .aiAnalysisFailed("Could not connect to Gemini."), retryAction: {})
}
