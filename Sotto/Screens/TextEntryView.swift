//
//  TextEntryView.swift
//  Sotto
//

import SwiftUI

struct TextEntryView: View {
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    @State private var showAnalysis = false
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack {
                TextEditor(text: $text)
                    .focused($isFocused)
                    .font(.body).fontDesign(.serif)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .scrollContentBackground(.hidden)

                // Word count and Done button
                HStack {
                    Text("\(text.split(separator: " ").count) words")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Button {
                        isFocused = false
                        showAnalysis = true
                    } label: {
                        Text("Done")
                            .font(.body).fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.sottoAccent, in: Capsule())
                    }
                    .disabled(text.isEmpty)
                    .opacity(text.isEmpty ? 0.5 : 1.0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .onAppear {
                isFocused = true
            }
            .fullScreenCover(isPresented: $showAnalysis) {
                AnalysisView(
                    transcript: text,
                    duration: 0, // No audio duration for text entries
                    wordCount: text.split(separator: " ").count,
                    onComplete: {
                        showAnalysis = false
                        dismiss()
                    }
                )
            }
        }
    }
}

#Preview {
    TextEntryView()
}
