//
//  OnboardingSourcesScreen.swift
//  Yattee
//
//  Third onboarding screen prompting users to explore settings.
//

import SwiftUI

struct OnboardingSourcesScreen: View {
    let onGoToSources: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Settings icon
            Image(systemName: "gearshape")
                .font(.system(size: 80))
                .foregroundStyle(Color.accentColor)

            // Title and description
            VStack(spacing: 12) {
                Text(String(localized: "onboarding.sources.title"))
                    .font(.title)
                    .fontWeight(.bold)

                Text(String(localized: "onboarding.sources.description"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                // Primary: Explore Settings
                Button(action: onGoToSources) {
                    Text(String(localized: "onboarding.sources.goToSettings"))
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

                // Secondary: Get Started
                Button(action: onClose) {
                    Text(String(localized: "onboarding.sources.later"))
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
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    OnboardingSourcesScreen(
        onGoToSources: {},
        onClose: {}
    )
}
