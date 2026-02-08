//
//  OnboardingTitleScreen.swift
//  Yattee
//
//  First onboarding screen with app logo, title, and feature highlights.
//

import SwiftUI

struct OnboardingTitleScreen: View {
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let iconSize = min(max(geometry.size.height * 0.13, 60), 140)
            let cornerRadius = iconSize * 0.23

            VStack(spacing: 32) {
                Spacer()

                // App icon and title
                VStack {
                    Image("AppIconPreview")
                        .resizable()
                        .scaledToFit()
                        .frame(width: iconSize, height: iconSize)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

                    Text(verbatim: "Yattee")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(String(localized: "onboarding.title.tagline"))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Feature highlights
                VStack(alignment: .leading, spacing: 20) {
                    FeatureRow(
                        icon: "lock.shield",
                        title: String(localized: "onboarding.title.privacy.title"),
                        description: String(localized: "onboarding.title.privacy.description")
                    )

                    FeatureRow(
                        icon: "server.rack",
                        title: String(localized: "onboarding.title.sources.title"),
                        description: String(localized: "onboarding.title.sources.description")
                    )

                    FeatureRow(
                        icon: "icloud",
                        title: String(localized: "onboarding.title.sync.title"),
                        description: String(localized: "onboarding.title.sync.description")
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)


                // Continue button
                Button(action: onContinue) {
                    Text(String(localized: "onboarding.continue"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingTitleScreen(onContinue: {})
}
