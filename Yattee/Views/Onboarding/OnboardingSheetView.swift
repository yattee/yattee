//
//  OnboardingSheetView.swift
//  Yattee
//
//  Container view for the onboarding flow with TabView and page dots.
//

import SwiftUI

struct OnboardingSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var currentPage = 0
    @State private var legacyItems: [LegacyImportItem]?
    @State private var hasCheckedLegacyData = false

    private var totalPages: Int {
        hasLegacyData ? 4 : 3
    }

    private var hasLegacyData: Bool {
        legacyItems?.isEmpty == false
    }

    private var settingsManager: SettingsManager? {
        appEnvironment?.settingsManager
    }

    private var legacyMigrationService: LegacyDataMigrationService? {
        appEnvironment?.legacyMigrationService
    }

    var body: some View {
        TabView(selection: $currentPage) {
            OnboardingTitleScreen(onContinue: advanceToNextPage)
                .tag(0)

            // Cloud screen is now always page 1 (before migration)
            // This ensures iCloud instances are synced before migration runs,
            // so isDuplicate() correctly detects duplicates against iCloud-synced instances
            OnboardingCloudScreen(onContinue: advanceToNextPage)
                .tag(1)

            // Migration screen is now page 2 (when present)
            if hasLegacyData, let binding = Binding($legacyItems) {
                OnboardingMigrationScreen(
                    items: binding,
                    onContinue: advanceToNextPage,
                    onSkip: advanceToNextPage
                )
                .tag(2)
            }

            OnboardingSourcesScreen(
                onGoToSources: goToSettings,
                onClose: completeOnboarding
            )
            .tag(hasLegacyData ? 3 : 2)
        }
        #if os(tvOS)
        .tabViewStyle(.page)
        #elseif os(iOS)
        .tabViewStyle(.page(indexDisplayMode: .never))
        #endif
        .interactiveDismissDisabled()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "onboarding.skip")) {
                    completeOnboarding()
                }
            }
        }
        .task {
            guard !hasCheckedLegacyData else { return }
            hasCheckedLegacyData = true
            legacyItems = legacyMigrationService?.parseLegacyData()
        }
    }

    // MARK: - Navigation

    private func advanceToNextPage() {
        withAnimation {
            if currentPage < totalPages - 1 {
                currentPage += 1
            } else {
                completeOnboarding()
            }
        }
    }

    private func completeOnboarding() {
        settingsManager?.onboardingCompleted = true
        dismiss()
    }

    private func goToSettings() {
        settingsManager?.onboardingCompleted = true
        dismiss()

        // Navigate to settings after dismiss completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(name: .showSettings, object: nil)
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let showOnboarding = Notification.Name("showOnboarding")
    static let showSettings = Notification.Name("showSettings")
    static let showOpenLinkSheet = Notification.Name("showOpenLinkSheet")
}

// MARK: - Preview

#Preview {
    @Previewable @State var sheetPresented: Bool = true
    
    VStack {
        
    }.sheet(isPresented: $sheetPresented) {
        OnboardingSheetView()
            .appEnvironment(.preview)
    }
}
