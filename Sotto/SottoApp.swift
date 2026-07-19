//
//  SottoApp.swift
//  Sotto
//
//  Created by Issa Abubakar on 15/07/2026.
//

import SwiftUI
import SwiftData

@main
struct SottoApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                SottoMainView()
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
            }
        }
        .modelContainer(for: JournalEntry.self)
    }
}
