//
//  MacOSSettings.swift
//  Yattee
//
//  Shared helpers that make Settings screens feel native on macOS while
//  keeping the iOS/tvOS Form-based layout unchanged.
//
//  The reference implementation these helpers mirror is SourcesListView.swift:
//  uppercase subheadline section headers, divider-bracketed cards (no rounded
//  background), and a ScrollView + LazyVStack container instead of Form.
//

import SwiftUI

/// Root container for a macOS-native settings screen.
///
/// - On macOS: renders a `ScrollView` + `LazyVStack` so sections can use
///   custom dividers and typography instead of Form's grouped cards.
/// - On iOS/tvOS: renders a standard `Form` (unchanged from the iOS layout).
struct SettingsFormContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if os(macOS)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        #else
        Form {
            content()
        }
        #endif
    }
}

/// A settings section with header and optional footer.
///
/// - On macOS: renders an uppercase `.subheadline` header, a top divider,
///   content with consistent padding, a bottom divider, and an optional
///   caption-sized footer.
/// - On iOS/tvOS: renders a standard `Section { } header: { } footer: { }`.
struct SettingsFormSection<Content: View>: View {
    let header: LocalizedStringKey?
    let footer: LocalizedStringKey?
    @ViewBuilder let content: () -> Content

    init(
        _ header: LocalizedStringKey? = nil,
        footer: LocalizedStringKey? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.header = header
        self.footer = footer
        self.content = content
    }

    var body: some View {
        #if os(macOS)
        macOSSection
        #else
        platformSection
        #endif
    }

    #if os(macOS)
    private var macOSSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                Text(header)
                    .font(.subheadline)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            }
        }
        .padding(.bottom, 12)
    }
    #else
    @ViewBuilder
    private var platformSection: some View {
        if let header, let footer {
            Section {
                content()
            } header: {
                Text(header)
            } footer: {
                Text(footer)
            }
        } else if let header {
            Section {
                content()
            } header: {
                Text(header)
            }
        } else if let footer {
            Section {
                content()
            } footer: {
                Text(footer)
            }
        } else {
            Section {
                content()
            }
        }
    }
    #endif
}
