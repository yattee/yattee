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
    @Environment(\.appEnvironment) private var appEnvironment

    @Binding var style: HomeShortcutCardStyle
    @Binding var color: HomeShortcutCardColor
    @Binding var palette: HomeShortcutColorfulPalette
    @Binding var customColors: [String]

    /// The user's accent color, used by the Accent palette (uniform fill).
    private var accentColor: Color {
        appEnvironment?.settingsManager.accentColor.color ?? .accentColor
    }

    /// Called after any value changes so the owner persists immediately. The
    /// owner sits covered in the navigation stack where its own onChange never
    /// fires, and swipe-dismissing the sheet from here skips its lifecycle.
    var onSave: (() -> Void)? = nil

    /// Editing mode for the custom palette.
    private enum CustomEditMode: String, CaseIterable {
        case list
        case text

        var displayName: LocalizedStringKey {
            switch self {
            case .list: return "home.shortcuts.palette.custom.mode.list"
            case .text: return "home.shortcuts.palette.custom.mode.text"
            }
        }
    }

    @State private var customEditMode: CustomEditMode = .list

    private let previewColumns = [GridItem(.adaptive(minimum: 150), spacing: 8)]

    /// All static shortcut types, previewed regardless of the user's current
    /// Home configuration so every style variation is visible.
    private let previewItems = HomeShortcutItem.defaultOrder

    var body: some View {
        List {
            Section {
                Picker(String(localized: "home.settings.shortcuts.layout"), selection: $style) {
                    ForEach(HomeShortcutCardStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                #if os(iOS)
                .pickerStyle(.segmented)
                #endif
            } header: {
                Text(String(localized: "home.settings.shortcuts.layout"))
            }

            Section {
                Picker(String(localized: "home.settings.shortcuts.color"), selection: $color) {
                    ForEach(HomeShortcutCardColor.allCases, id: \.self) { color in
                        Text(color.displayName).tag(color)
                    }
                }
                #if os(iOS)
                .pickerStyle(.segmented)
                #endif
            } header: {
                Text(String(localized: "home.settings.shortcuts.color"))
            }

            paletteSection

            if palette == .custom {
                customColorsSection
            }

            Section {
                LazyVGrid(columns: previewColumns, spacing: 8) {
                    ForEach(Array(previewItems.enumerated()), id: \.element.id) { index, item in
                        HomeShortcutCardView(
                            icon: item.icon,
                            title: item.localizedTitle,
                            count: sampleCount(for: item),
                            subtitle: sampleSubtitle(for: item),
                            showsCount: showsCount(for: item),
                            colorfulColor: item.cardColor,
                            styleOverride: style,
                            colorOverride: color
                        )
                        .environment(
                            \.homeShortcutColorfulColor,
                            HomeShortcutColorfulPalette.color(forPosition: index, palette: palette, customHex: customColors, accentColor: accentColor)
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
        .onChange(of: style) { onSave?() }
        .onChange(of: color) { onSave?() }
        .onChange(of: palette) { onSave?() }
        .onChange(of: customColors) { onSave?() }
    }

    // MARK: - Palette

    private var paletteSection: some View {
        Section {
            Picker(String(localized: "home.settings.shortcuts.palette"), selection: $palette) {
                ForEach(HomeShortcutColorfulPalette.allCases, id: \.self) { palette in
                    Text(palette.displayName).tag(palette)
                }
            }

            // Swatch strip for the selected palette.
            swatchStrip(for: paletteSwatchColors)
                .padding(.vertical, 4)
        } header: {
            Text(String(localized: "home.settings.shortcuts.palette"))
        }
    }

    /// Colors shown in the selected-palette swatch strip.
    private var paletteSwatchColors: [Color] {
        if palette == .accent {
            return [accentColor]
        }
        if palette == .custom {
            let parsed = customColors.compactMap { Color(hex: $0) }
            return parsed.isEmpty ? (HomeShortcutColorfulPalette.classic.builtInColors ?? []) : parsed
        }
        return palette.builtInColors ?? []
    }

    private func swatchStrip(for colors: [Color]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                RoundedRectangle(cornerRadius: 5)
                    .fill(color)
                    .frame(height: 22)
            }
        }
    }

    // MARK: - Custom Colors

    private var customColorsSection: some View {
        Section {
            Picker(String(localized: "home.shortcuts.palette.custom.mode"), selection: $customEditMode) {
                ForEach(CustomEditMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch customEditMode {
            case .list:
                ForEach(customColors.indices, id: \.self) { index in
                    customColorRow(index: index)
                }
                .onDelete { offsets in
                    customColors.remove(atOffsets: offsets)
                }

                Button {
                    let seed = HomeShortcutColorfulPalette.customStarterColors.first ?? "#4D96FF"
                    customColors.append(seed)
                } label: {
                    Label(String(localized: "home.shortcuts.palette.custom.add"), systemImage: "plus.circle.fill")
                }

            case .text:
                TextField(
                    String(localized: "home.shortcuts.palette.custom.placeholder"),
                    text: customColorsText,
                    axis: .vertical
                )
                .lineLimit(3 ... 6)
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                #endif
                .font(.body.monospaced())
            }
        } header: {
            Text(String(localized: "home.shortcuts.palette.custom.header"))
        } footer: {
            Text(String(localized: "home.shortcuts.palette.custom.footer"))
        }
    }

    private func customColorRow(index: Int) -> some View {
        HStack(spacing: 12) {
            ColorPicker("", selection: colorBinding(at: index), supportsOpacity: false)
                .labelsHidden()

            TextField("#RRGGBB", text: hexBinding(at: index))
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                #endif
                .font(.body.monospaced())

            Spacer(minLength: 0)

            Button(role: .destructive) {
                guard customColors.indices.contains(index) else { return }
                customColors.remove(at: index)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Bindings

    /// Two-way binding between a stored hex string and a SwiftUI Color for the
    /// native ColorPicker.
    private func colorBinding(at index: Int) -> Binding<Color> {
        Binding(
            get: {
                guard customColors.indices.contains(index) else { return .gray }
                return Color(hex: customColors[index]) ?? .gray
            },
            set: { newColor in
                guard customColors.indices.contains(index) else { return }
                customColors[index] = newColor.toHexString()
            }
        )
    }

    /// Editable hex text for a single custom color.
    private func hexBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard customColors.indices.contains(index) else { return "" }
                return customColors[index]
            },
            set: { newValue in
                guard customColors.indices.contains(index) else { return }
                customColors[index] = newValue
            }
        )
    }

    /// Comma/newline separated hex list for the text-editing mode.
    private var customColorsText: Binding<String> {
        Binding(
            get: { customColors.joined(separator: ", ") },
            set: { newValue in
                customColors = newValue
                    .split(whereSeparator: { $0 == "," || $0 == "\n" })
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    // MARK: - Preview Helpers

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

    /// Representative count so the Regular (Reminders-style) layout looks
    /// realistic in the preview.
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

    /// The count subtitle shown on real Compact cards, mirroring `HomeView`'s
    /// per-item subtitles so the Compact preview shows its second line.
    private func sampleSubtitle(for item: HomeShortcutItem) -> String {
        switch item {
        case .openURL, .remoteControl:
            return ""
        case .playlists:
            return formatCount(sampleCount(for: item), singular: "home.count.playlist", plural: "home.count.playlists")
        case .bookmarks:
            return formatCount(sampleCount(for: item), singular: "home.count.bookmark", plural: "home.count.bookmarks")
        case .continueWatching, .history:
            return formatCount(sampleCount(for: item), singular: "home.count.video", plural: "home.count.videos")
        case .downloads:
            return formatCount(sampleCount(for: item), singular: "home.count.video", plural: "home.count.videos")
        case .channels:
            return formatCount(sampleCount(for: item), singular: "home.count.channel", plural: "home.count.channels")
        case .subscriptions:
            return String(localized: "home.subscriptions.subtitle")
        case .mediaSources:
            return sampleCount(for: item) == 1 ? "1 source" : "\(sampleCount(for: item)) sources"
        case .instanceContent, .mediaSource:
            return ""
        }
    }

    /// Localized "N items" string, mirroring `HomeView.formatCount`.
    private func formatCount(_ count: Int, singular: String.LocalizationValue, plural: String.LocalizationValue) -> String {
        let formattedCount = CountFormatter.compact(count)
        let key = count == 1 ? singular : plural
        return String(localized: "\(formattedCount) \(String(localized: key))")
    }
}

#Preview {
    NavigationStack {
        HomeShortcutStyleView(
            style: .constant(.regular),
            color: .constant(.vibrant),
            palette: .constant(.classic),
            customColors: .constant(HomeShortcutColorfulPalette.customStarterColors)
        )
        .appEnvironment(.preview)
    }
}
#endif
