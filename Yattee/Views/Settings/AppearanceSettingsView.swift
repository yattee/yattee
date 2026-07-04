//
//  AppearanceSettingsView.swift
//  Yattee
//
//  Appearance settings with theme and accent color selection.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AppearanceSettingsView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        SettingsFormContainer {
            if let settings = appEnvironment?.settingsManager {
                // Theme section
                #if !os(tvOS)
                ThemeSection(settings: settings)
                #endif

                // App icon section
                #if !os(tvOS)
                AppIconSection(settings: settings)
                #endif

                // Accent color section
                #if !os(tvOS)
                AccentColorSection(settings: settings)
                #endif

                // List style section
                #if !os(tvOS)
                ListStyleSection(settings: settings)
                #endif

                // Thumbnail section
                ThumbnailSection(settings: settings)
            }
        }
        #if !os(tvOS)
        .navigationTitle(String(localized: "settings.appearance.title"))
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Theme Section

private struct ThemeSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        SettingsFormSection("settings.appearance.theme.header") {
            Picker(
                String(localized: "settings.appearance.theme"),
                selection: $settings.theme
            ) {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

// MARK: - App Icon Section

#if !os(tvOS)
private struct AppIconSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        SettingsFormSection("settings.appearance.appIcon.header") {
            NavigationLink {
                AppIconPickerView(settings: settings)
            } label: {
                HStack {
                    Image(settings.appIcon.previewImageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Text(settings.appIcon.displayName)
                }
            }
        }
    }
}

private struct AppIconPickerView: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        List {
            ForEach(AppIcon.allCases, id: \.self) { appIcon in
                Button {
                    settings.appIcon = appIcon
                } label: {
                    HStack {
                        Image(appIcon.previewImageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 13.5))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(appIcon.displayName)
                                .foregroundStyle(.primary)

                            if let author = appIcon.author {
                                Text(author)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if settings.appIcon == appIcon {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(String(localized: "settings.appearance.appIcon.header"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
#endif

// MARK: - Accent Color Section

private struct AccentColorSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        SettingsFormSection("settings.appearance.accentColor.header") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: 16) {
                ForEach(AccentColor.presets, id: \.self) { accentColor in
                    AccentColorButton(
                        accentColor: accentColor,
                        isSelected: settings.accentColor == accentColor,
                        onSelect: { settings.accentColor = accentColor }
                    )
                }

                #if !os(tvOS)
                CustomAccentColorButton(settings: settings)
                #endif
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - List Style Section

private struct ListStyleSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        SettingsFormSection("settings.appearance.listStyle.header") {
            Picker(selection: $settings.listStyle) {
                ForEach(VideoListStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            } label: {
                Label(String(localized: "settings.appearance.listStyle"), systemImage: "list.bullet")
            }
        }
    }
}

// MARK: - Thumbnail Section

private struct ThumbnailSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        SettingsFormSection("settings.appearance.thumbnails.header") {
            Toggle(isOn: $settings.showWatchedCheckmark) {
                Label(String(localized: "settings.appearance.showWatchedCheckmark"),
                      systemImage: "checkmark.circle.fill")
            }
        }
    }
}

// MARK: - Accent Color Button

private struct AccentColorButton: View {
    let accentColor: AccentColor
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                Circle()
                    .fill(accentColor.color)
                    .frame(width: 40, height: 40)

                if isSelected {
                    Circle()
                        .strokeBorder(.white, lineWidth: 3)
                        .frame(width: 40, height: 40)

                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accentColor.displayName)
    }
}

// MARK: - Custom Accent Color Button

#if !os(tvOS)
private struct CustomAccentColorButton: View {
    @Bindable var settings: SettingsManager

    private var isSelected: Bool { settings.accentColor == .custom }

    #if os(macOS)
    var body: some View {
        Button {
            settings.accentColor = .custom
            ColorPanelBridge.shared.open(with: NSColor(settings.customAccentColor)) { nsColor in
                settings.customAccentColor = Color(nsColor: nsColor)
                settings.accentColor = .custom
            }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                            center: .center
                        ),
                        lineWidth: 4
                    )
                    .frame(width: 40, height: 40)

                Circle()
                    .fill(settings.customAccentColor)
                    .frame(width: 28, height: 28)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "settings.appearance.accentColor.custom"))
    }
    #else
    private var pickedColor: Binding<Color> {
        Binding(
            get: { settings.customAccentColor },
            set: { newColor in
                settings.customAccentColor = newColor
                settings.accentColor = .custom
            }
        )
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(settings.customAccentColor)
                .frame(width: 40, height: 40)
                .opacity(isSelected ? 1 : 0)

            ColorPicker(
                String(localized: "settings.appearance.accentColor.custom"),
                selection: pickedColor,
                supportsOpacity: false
            )
            .labelsHidden()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel(String(localized: "settings.appearance.accentColor.custom"))
    }
    #endif
}

#if os(macOS)
/// Routes NSColorPanel target/action callbacks to the settings binding.
/// NSColorPanel keeps only a weak target, so this must outlive the view.
@MainActor
private final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()
    private var onChange: ((NSColor) -> Void)?

    func open(with color: NSColor, onChange: @escaping (NSColor) -> Void) {
        self.onChange = onChange
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = color
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        onChange?(sender.color)
    }
}
#endif
#endif

// MARK: - Theme Display Names

extension AppTheme {
    var displayName: String {
        switch self {
        case .system: return String(localized: "settings.appearance.theme.system")
        case .light: return String(localized: "settings.appearance.theme.light")
        case .dark: return String(localized: "settings.appearance.theme.dark")
        }
    }
}

// MARK: - Ambient Glow Section

// MARK: - Accent Color Display Names

extension AccentColor {
    var displayName: String {
        switch self {
        case .default: return String(localized: "settings.appearance.accentColor.default")
        case .red: return String(localized: "settings.appearance.accentColor.red")
        case .pink: return String(localized: "settings.appearance.accentColor.pink")
        case .orange: return String(localized: "settings.appearance.accentColor.orange")
        case .yellow: return String(localized: "settings.appearance.accentColor.yellow")
        case .green: return String(localized: "settings.appearance.accentColor.green")
        case .teal: return String(localized: "settings.appearance.accentColor.teal")
        case .blue: return String(localized: "settings.appearance.accentColor.blue")
        case .purple: return String(localized: "settings.appearance.accentColor.purple")
        case .indigo: return String(localized: "settings.appearance.accentColor.indigo")
        case .custom: return String(localized: "settings.appearance.accentColor.custom")
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
    .appEnvironment(.preview)
}
