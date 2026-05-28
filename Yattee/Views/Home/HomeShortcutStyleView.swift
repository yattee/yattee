//
//  HomeShortcutStyleView.swift
//  Yattee
//
//  Dedicated page for choosing the Home shortcut card style, with a live
//  non-interactive preview of every shortcut type in the selected style.
//

#if !os(tvOS)
import SwiftUI

struct HomeShortcutStyleView: View {
    @Binding var style: HomeShortcutCardStyle

    private let previewColumns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    /// All static shortcut types, previewed regardless of the user's current
    /// Home configuration so every style variation is visible.
    private let previewItems = HomeShortcutItem.defaultOrder

    var body: some View {
        List {
            Section {
                Picker(String(localized: "home.settings.shortcuts.style"), selection: $style) {
                    ForEach(HomeShortcutCardStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                #if os(iOS)
                .pickerStyle(.segmented)
                #endif
            }

            Section {
                LazyVGrid(columns: previewColumns, spacing: 16) {
                    ForEach(previewItems) { item in
                        HomeShortcutCardView(
                            icon: item.icon,
                            title: item.localizedTitle,
                            count: sampleCount(for: item),
                            subtitle: "",
                            showsCount: showsCount(for: item),
                            colorfulColor: item.cardColor,
                            styleOverride: style
                        )
                    }
                }
                .padding(.vertical, 4)
                .allowsHitTesting(false)
            } header: {
                Text(String(localized: "home.settings.shortcuts.style.preview"))
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #endif
        .navigationTitle(String(localized: "home.settings.shortcuts.style"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// Shortcuts without a meaningful count hide it in the filled layout,
    /// mirroring `HomeView`'s real card configuration.
    private func showsCount(for item: HomeShortcutItem) -> Bool {
        switch item {
        case .openURL, .remoteControl, .subscriptions:
            return false
        default:
            return true
        }
    }

    /// Representative count so the accent/colorful (Reminders-style) layout
    /// looks realistic in the preview.
    private func sampleCount(for item: HomeShortcutItem) -> Int {
        switch item {
        case .playlists: return 8
        case .bookmarks: return 12
        case .continueWatching: return 3
        case .history: return 42
        case .downloads: return 5
        case .channels: return 24
        case .mediaSources: return 2
        default: return 0
        }
    }
}

#Preview {
    NavigationStack {
        HomeShortcutStyleView(style: .constant(.colorful))
            .appEnvironment(.preview)
    }
}
#endif
