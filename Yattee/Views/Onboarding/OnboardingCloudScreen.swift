//
//  OnboardingCloudScreen.swift
//  Yattee
//
//  Second onboarding screen for iCloud sync configuration.
//

import CloudKit
import SwiftUI

struct OnboardingCloudScreen: View {
    @Environment(\.appEnvironment) private var appEnvironment
    let onContinue: () -> Void

    private enum ScreenState: Equatable {
        case initial      // Show enable/skip buttons
        case syncing      // Show progress view
        case complete     // Sync finished, show continue
        case error(String) // Show error with continue option
    }

    @State private var screenState: ScreenState = .initial
    @State private var iCloudAvailable: Bool?
    @State private var isChecking = true

    private var settingsManager: SettingsManager? {
        appEnvironment?.settingsManager
    }

    private var cloudKitSync: CloudKitSyncEngine? {
        appEnvironment?.cloudKitSync
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Content based on state
            switch screenState {
            case .initial:
                initialView
            case .syncing:
                syncingView
            case .complete:
                completeView
            case .error(let message):
                errorView(message)
            }

            Spacer()

            // Buttons based on state
            buttonsForState
        }
        .padding()
        .task {
            await checkiCloudAvailability()
        }
        .onChange(of: cloudKitSync?.uploadProgress?.isComplete) { _, newValue in
            if newValue == true {
                withAnimation {
                    screenState = .complete
                }
            }
        }
    }

    // MARK: - Initial View

    @ViewBuilder
    private var initialView: some View {
        // iCloud icon
        Image(systemName: "icloud")
            .font(.system(size: 80))
            .foregroundStyle(Color.accentColor)

        // Title and description
        VStack(spacing: 12) {
            Text(String(localized: "onboarding.cloud.title"))
                .font(.title)
                .fontWeight(.bold)

            Text(String(localized: "onboarding.cloud.description"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }

        // iCloud status indicator
        VStack(spacing: 16) {
            if isChecking {
                ProgressView()
                    .controlSize(.large)
            } else if iCloudAvailable == false {
                // iCloud unavailable
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.icloud")
                        .font(.title)
                        .foregroundStyle(.orange)

                    Text(String(localized: "onboarding.cloud.unavailable"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                #if os(tvOS)
                .background(Color(.systemGray).opacity(0.2))
                #elseif os(macOS)
                .background(Color(nsColor: .controlBackgroundColor))
                #else
                .background(Color(uiColor: .secondarySystemBackground))
                #endif
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Syncing View

    @ViewBuilder
    private var syncingView: some View {
        // Animated iCloud icon
        Image(systemName: "icloud")
            .font(.system(size: 80))
            .foregroundStyle(Color.accentColor)
            .symbolEffect(.pulse)

        // Syncing title and progress
        VStack(spacing: 12) {
            Text(String(localized: "onboarding.cloud.syncing.title"))
                .font(.title)
                .fontWeight(.bold)

            // Show appropriate progress text based on sync phase
            if cloudKitSync?.isReceivingChanges == true {
                Text(String(localized: "onboarding.cloud.syncing.downloading"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if let progress = cloudKitSync?.uploadProgress {
                Text(progress.displayText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text(String(localized: "onboarding.cloud.syncing.preparing"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            ProgressView()
                .controlSize(.large)
                .padding(.top, 8)
        }
    }

    // MARK: - Complete View

    @ViewBuilder
    private var completeView: some View {
        // Checkmark iCloud icon
        Image(systemName: "checkmark.icloud")
            .font(.system(size: 80))
            .foregroundStyle(.green)

        // Complete title and description
        VStack(spacing: 12) {
            Text(String(localized: "onboarding.cloud.complete.title"))
                .font(.title)
                .fontWeight(.bold)

            Text(String(localized: "onboarding.cloud.complete.description"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        // Warning iCloud icon
        Image(systemName: "exclamationmark.icloud")
            .font(.system(size: 80))
            .foregroundStyle(.orange)

        // Error title and message
        VStack(spacing: 12) {
            Text(String(localized: "onboarding.cloud.error.title"))
                .font(.title)
                .fontWeight(.bold)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    // MARK: - Buttons

    @ViewBuilder
    private var buttonsForState: some View {
        switch screenState {
        case .initial:
            if isChecking {
                EmptyView()
            } else if iCloudAvailable == true {
                // Two buttons: Enable iCloud (primary) and Skip (secondary)
                VStack(spacing: 12) {
                    // Primary: Enable iCloud
                    Button(action: enableAndStartSync) {
                        Text(String(localized: "onboarding.cloud.enable"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            #if os(tvOS)
                            .background(Color.accentColor.opacity(0.2))
                            #else
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            #endif
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    #if os(tvOS)
                    .buttonStyle(.card)
                    #endif

                    // Secondary: Skip for now
                    Button(action: onContinue) {
                        Text(String(localized: "onboarding.cloud.skip"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            #if os(tvOS)
                            .background(Color(.systemGray).opacity(0.2))
                            #elseif os(macOS)
                            .background(Color(nsColor: .controlBackgroundColor))
                            #else
                            .background(Color(uiColor: .secondarySystemBackground))
                            #endif
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    #if os(tvOS)
                    .buttonStyle(.card)
                    #endif
                }
                .padding(.horizontal)
                .padding(.bottom)
            } else {
                // iCloud unavailable - just show Continue
                Button(action: onContinue) {
                    Text(String(localized: "onboarding.continue"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        #if os(tvOS)
                        .background(Color.accentColor.opacity(0.2))
                        #else
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        #endif
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                #if os(tvOS)
                .buttonStyle(.card)
                #endif
                .padding(.horizontal)
                .padding(.bottom)
            }

        case .syncing:
            // No continue button during sync - user must wait
            // (toolbar Skip still available to exit onboarding)
            EmptyView()

        case .complete, .error:
            // Continue button
            Button(action: onContinue) {
                Text(String(localized: "onboarding.continue"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    #if os(tvOS)
                    .background(Color.accentColor.opacity(0.2))
                    #else
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    #endif
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            #if os(tvOS)
            .buttonStyle(.card)
            #endif
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    // MARK: - iCloud

    private func checkiCloudAvailability() async {
        do {
            let status = try await CKContainer.default().accountStatus()
            iCloudAvailable = (status == .available)
        } catch {
            iCloudAvailable = false
        }
        isChecking = false
    }

    private func enableAndStartSync() {
        // Transition to syncing state
        withAnimation {
            screenState = .syncing
        }

        settingsManager?.iCloudSyncEnabled = true
        settingsManager?.enableAllSyncCategories()

        // Enable CloudKit sync engine then trigger initial upload
        Task {
            await appEnvironment?.cloudKitSync.enable()
            await appEnvironment?.cloudKitSync.performInitialUpload()
        }

        // Sync non-CloudKit data
        settingsManager?.replaceWithiCloudData()
        appEnvironment?.instancesManager.replaceWithiCloudData()
        appEnvironment?.mediaSourcesManager.replaceWithiCloudData()
    }
}

// MARK: - Preview

#Preview {
    OnboardingCloudScreen(onContinue: {})
        .appEnvironment(.preview)
}
