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
        .opaqueWindowBackground()
        #else
        Form {
            content()
        }
        #endif
    }
}

extension View {
    /// Unified background for settings pages whose root is a `Form` or `List`.
    ///
    /// On macOS those containers draw their own translucent scroll background
    /// (wallpaper-tinted) on top of any background placed behind them, so it
    /// has to be hidden before the opaque window background can show through.
    /// No-op on iOS/tvOS.
    func opaqueSettingsFormBackground() -> some View {
        #if os(macOS)
        return scrollContentBackground(.hidden).opaqueWindowBackground()
        #else
        return self
        #endif
    }
}

/// A settings section with header and optional footer.
///
/// - On macOS: renders an uppercase `.subheadline` header, a top divider,
///   content with consistent padding, a bottom divider, and an optional
///   caption-sized footer.
/// - On iOS/tvOS: renders a standard `Section { } header: { } footer: { }`.
struct SettingsFormSection<Content: View, Footer: View>: View {
    let header: LocalizedStringKey?
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

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

                Divider()
            }

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            footer()
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 6)
        }
        .padding(.bottom, 12)
    }
    #else
    @ViewBuilder
    private var platformSection: some View {
        if let header {
            Section {
                content()
            } header: {
                Text(header)
            } footer: {
                footer()
            }
        } else {
            Section {
                content()
            } footer: {
                footer()
            }
        }
    }
    #endif
}

extension SettingsFormSection where Footer == EmptyView {
    init(
        _ header: LocalizedStringKey? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.header = header
        self.content = content
        self.footer = { EmptyView() }
    }
}

extension SettingsFormSection where Footer == Text {
    init(
        _ header: LocalizedStringKey? = nil,
        footer: LocalizedStringKey,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.header = header
        self.content = content
        self.footer = { Text(footer) }
    }

    init(
        _ header: LocalizedStringKey? = nil,
        footer: LocalizedStringKey?,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.header = header
        self.content = content
        let footerKey = footer
        self.footer = { footerKey.map { Text($0) } ?? Text(verbatim: "") }
    }
}

extension SettingsFormSection {
    init(
        _ header: LocalizedStringKey? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.header = header
        self.content = content
        self.footer = footer
    }
}

/// A label style that forces the icon to a fixed width so adjacent
/// labels align regardless of icon glyph width. Use when a section has
/// a vertical stack of `Label`s with mixed-width SF Symbols.
struct FixedIconWidthLabelStyle: LabelStyle {
    var iconWidth: CGFloat = 22

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .frame(width: iconWidth, alignment: .center)
            configuration.title
        }
    }
}

/// A settings row that pushes a destination view onto the navigation stack.
///
/// On macOS it renders as a plain full-width list row with a trailing
/// chevron, matching the native macOS System Settings look. On iOS/tvOS
/// it renders as a standard `NavigationLink` with a `Label`.
struct SettingsNavigationRow<Destination: View, Trailing: View>: View {
    let titleKey: LocalizedStringKey
    let systemImage: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var destination: () -> Destination

    init(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.trailing = trailing
        self.destination = destination
    }

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            #if os(macOS)
            HStack(spacing: 8) {
                Label(titleKey, systemImage: systemImage)
                Spacer()
                trailing()
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            #else
            HStack {
                Label(titleKey, systemImage: systemImage)
                Spacer()
                trailing()
                    .foregroundStyle(.secondary)
            }
            #endif
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
    }
}
