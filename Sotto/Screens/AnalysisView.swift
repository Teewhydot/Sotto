//
//  AnalysisView.swift
//  Sotto
//

import SwiftUI
import Combine

struct AnalysisView: View {
    @Environment(\.dismiss) var dismiss

    @State private var scale: CGFloat = 0.85
    @State private var opacity: Double = 0.35
    @State private var rippleScale: CGFloat = 0.6
    @State private var rippleOpacity: Double = 0.0
    @State private var showDone = false

    // Auto-dismiss after 2.5s to simulate analysis completing
    let dismissTimer = Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 36) {
                Spacer()

                // Pulsing ring + dot
                ZStack {
                    // Outer ripple ring
                    Circle()
                        .stroke(Color.sottoAccent.opacity(rippleOpacity), lineWidth: 1.5)
                        .frame(width: 72, height: 72)
                        .scaleEffect(rippleScale)
                        .onAppear {
                            withAnimation(
                                .easeOut(duration: 1.4).repeatForever(autoreverses: false)
                            ) {
                                rippleScale = 1.8
                                rippleOpacity = 0
                            }
                        }

                    // Inner dot
                    Circle()
                        .fill(Color.sottoAccent)
                        .frame(width: 22, height: 22)
                        .scaleEffect(scale)
                        .opacity(opacity)
                        .onAppear {
                            withAnimation(
                                .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                            ) {
                                scale = 1.25
                                opacity = 1.0
                            }
                        }
                }

                VStack(spacing: 10) {
                    Text("Sotto is with you.")
                        .font(.title3).fontWeight(.medium).fontDesign(.rounded)
                        .foregroundStyle(.primary)

                    Text("Reflecting on what you shared…")
                        .font(.subheadline).fontDesign(.rounded)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Stats
                HStack(spacing: 14) {
                    Text("214 words")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text("·").foregroundStyle(Color(.quaternaryLabel))
                    Text("1m 47s")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Spacer().frame(height: 44)
            }
        }
        .onReceive(dismissTimer) { _ in
            dismiss()
        }
    }
}

#Preview("Analysis") {
    AnalysisView()
}
