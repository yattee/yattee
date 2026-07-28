//
//  SubtitlesSettingsView.swift
//  Yattee
//
//  Settings view for configuring subtitle appearance in MPV player.
//

import SwiftUI

struct SubtitlesSettingsView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var settings: SubtitleSettings = .default

    var body: some View {
        SettingsFormContainer {
            fontSection
            colorsSection
            styleSection
            positionSection
            resetSection
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .navigationTitle(String(localized: "settings.subtitles.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            if let settingsManager = appEnvironment?.settingsManager {
                settings = settingsManager.subtitleSettings
            }
        }
    }

    // MARK: - Font Section

    private var fontSection: some View {
        SettingsFormSection {
            PlatformMenuPicker(
                String(localized: "settings.subtitles.font"),
                selection: $settings.font
            ) {
                ForEach(SubtitleFont.allCases, id: \.self) { font in
                    Text(font.displayName).tag(font)
                }
            }
            .onChange(of: settings.font) { _, _ in saveSettings() }

            #if os(tvOS)
            // tvOS uses Picker instead of Slider (Slider unavailable)
            PlatformMenuPicker(String(localized: "settings.subtitles.fontSize"), selection: $settings.fontSize) {
                ForEach([20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100], id: \.self) { size in
                    Text("settings.subtitles.fontSize \(size)").tag(size)
                }
            }
            .onChange(of: settings.fontSize) { _, _ in saveSettings() }
            #else
            VStack(alignment: .leading) {
                Text(String(localized: "settings.subtitles.fontSize"))
                HStack {
                    Slider(
                        value: Binding(
                            get: { Double(settings.fontSize) },
                            set: { settings.fontSize = Int($0) }
                        ),
                        in: 20...100,
                        step: 1
                    )
                    .onChange(of: settings.fontSize) { _, _ in saveSettings() }
                    TextField("", value: $settings.fontSize, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .multilineTextAlignment(.center)
                        .onChange(of: settings.fontSize) { _, _ in saveSettings() }
                    Text(String(localized: "common.unit.points"))
                        .foregroundStyle(.secondary)
                }
            }
            #endif
        }
    }

    // MARK: - Colors Section

    private var colorsSection: some View {
        SettingsFormSection("settings.subtitles.colorsSection") {
            #if os(tvOS)
            colorPresetPicker(
                "settings.subtitles.textColor",
                color: Binding(
                    get: { settings.textColor },
                    set: {
                        settings.textColor = $0
                        saveSettings()
                    }
                )
            )

            colorPresetPicker(
                "settings.subtitles.borderColor",
                color: Binding(
                    get: { settings.borderColor },
                    set: {
                        settings.borderColor = $0
                        saveSettings()
                    }
                )
            )

            PlatformMenuPicker(String(localized: "settings.subtitles.borderSize"), selection: $settings.borderSize) {
                ForEach(Array(stride(from: 0.0, through: 5.0, by: 0.5)), id: \.self) { size in
                    Text(String(format: "%.1f", size)).tag(size)
                }
            }
            .onChange(of: settings.borderSize) { _, _ in saveSettings() }
            #else
            ColorPicker(
                String(localized: "settings.subtitles.textColor"),
                selection: Binding(
                    get: { settings.textColor.color },
                    set: {
                        settings.textColor = CodableColor($0)
                        saveSettings()
                    }
                ),
                supportsOpacity: false
            )

            ColorPicker(
                String(localized: "settings.subtitles.borderColor"),
                selection: Binding(
                    get: { settings.borderColor.color },
                    set: {
                        settings.borderColor = CodableColor($0)
                        saveSettings()
                    }
                ),
                supportsOpacity: false
            )

            VStack(alignment: .leading) {
                Text(String(localized: "settings.subtitles.borderSize"))
                HStack {
                    Slider(value: $settings.borderSize, in: 0...5, step: 0.5)
                        .onChange(of: settings.borderSize) { _, _ in saveSettings() }
                    Text(String(format: "%.1f", settings.borderSize))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 30)
                }
            }
            #endif

            Toggle(
                String(localized: "settings.subtitles.showBackground"),
                isOn: $settings.showBackground
            )
            .onChange(of: settings.showBackground) { _, _ in saveSettings() }

            #if os(tvOS)
            if settings.showBackground {
                colorPresetPicker(
                    "settings.subtitles.backgroundColor",
                    color: Binding(
                        get: { settings.backgroundColor },
                        set: {
                            // Preserve the stored opacity; it's controlled by the opacity picker below.
                            settings.backgroundColor = CodableColor(
                                red: $0.red,
                                green: $0.green,
                                blue: $0.blue,
                                opacity: settings.backgroundColor.opacity
                            )
                            saveSettings()
                        }
                    )
                )

                PlatformMenuPicker(
                    String(localized: "settings.subtitles.backgroundOpacity"),
                    selection: backgroundOpacity
                ) {
                    ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { opacity in
                        Text(verbatim: "\(Int(opacity * 100))%").tag(opacity)
                    }
                }
            }
            #else
            if settings.showBackground {
                ColorPicker(
                    String(localized: "settings.subtitles.backgroundColor"),
                    selection: Binding(
                        get: { settings.backgroundColor.color },
                        set: {
                            settings.backgroundColor = CodableColor($0)
                            saveSettings()
                        }
                    ),
                    supportsOpacity: true
                )
            }
            #endif
        }
    }

    // MARK: - Style Section

    private var styleSection: some View {
        SettingsFormSection("settings.subtitles.styleSection") {
            Toggle(
                String(localized: "settings.subtitles.bold"),
                isOn: $settings.isBold
            )
            .onChange(of: settings.isBold) { _, _ in saveSettings() }

            Toggle(
                String(localized: "settings.subtitles.italic"),
                isOn: $settings.isItalic
            )
            .onChange(of: settings.isItalic) { _, _ in saveSettings() }
        }
    }

    // MARK: - Position Section

    private var positionSection: some View {
        SettingsFormSection("settings.subtitles.positionSection", footer: "settings.subtitles.positionFooter") {
            #if os(tvOS)
            PlatformMenuPicker(String(localized: "settings.subtitles.positionSection"), selection: $settings.bottomMargin) {
                ForEach(Array(stride(from: 0, through: 50, by: 5)), id: \.self) { margin in
                    Text(verbatim: "\(margin)%").tag(margin)
                }
            }
            .onChange(of: settings.bottomMargin) { _, _ in saveSettings() }
            #else
            Stepper(
                String(localized: "settings.subtitles.bottomMargin \(settings.bottomMargin)"),
                value: $settings.bottomMargin,
                in: 0...50,
                step: 5
            )
            .onChange(of: settings.bottomMargin) { _, _ in saveSettings() }
            #endif
        }
    }

    // MARK: - Reset Section

    private var resetSection: some View {
        SettingsFormSection {
            Button(role: .destructive) {
                settings = .default
                saveSettings()
            } label: {
                HStack {
                    Spacer()
                    Text(String(localized: "settings.subtitles.resetToDefaults"))
                    Spacer()
                }
            }
        }
    }

    // MARK: - tvOS Helpers

    #if os(tvOS)
    /// A menu picker over the preset palette, with a swatch of the current color in the label.
    private func colorPresetPicker(_ titleKey: String.LocalizationValue, color: Binding<CodableColor>) -> some View {
        PlatformMenuPicker(
            selection: Binding(
                get: { SubtitleColorPreset.nearest(to: color.wrappedValue) },
                set: { color.wrappedValue = $0.codableColor }
            )
        ) {
            ForEach(SubtitleColorPreset.allCases, id: \.self) { preset in
                Text(preset.displayName).tag(preset)
            }
        } label: {
            HStack {
                Text(String(localized: titleKey))
                Circle()
                    .fill(color.wrappedValue.color)
                    .frame(width: 24, height: 24)
            }
        }
    }

    /// Background opacity snapped to the picker's preset steps.
    private var backgroundOpacity: Binding<Double> {
        Binding(
            get: {
                [0.25, 0.5, 0.75, 1.0].min {
                    abs($0 - settings.backgroundColor.opacity) < abs($1 - settings.backgroundColor.opacity)
                } ?? 0.75
            },
            set: {
                settings.backgroundColor = CodableColor(
                    red: settings.backgroundColor.red,
                    green: settings.backgroundColor.green,
                    blue: settings.backgroundColor.blue,
                    opacity: $0
                )
                saveSettings()
            }
        )
    }
    #endif

    // MARK: - Helpers

    private func saveSettings() {
        appEnvironment?.settingsManager.subtitleSettings = settings

        // Apply changes to active MPV player immediately
        if let mpvBackend = appEnvironment?.playerService.currentBackend as? MPVBackend {
            mpvBackend.updateSubtitleSettings()
        }
    }
}

// MARK: - tvOS Color Presets

#if os(tvOS)
/// Preset colors for subtitle settings on tvOS, where ColorPicker is unavailable.
private enum SubtitleColorPreset: String, CaseIterable {
    case white
    case yellow
    case orange
    case red
    case magenta
    case blue
    case cyan
    case green
    case black

    var displayName: String {
        switch self {
        case .white:
            return String(localized: "settings.subtitles.color.white")
        case .yellow:
            return String(localized: "settings.subtitles.color.yellow")
        case .orange:
            return String(localized: "settings.subtitles.color.orange")
        case .red:
            return String(localized: "settings.subtitles.color.red")
        case .magenta:
            return String(localized: "settings.subtitles.color.magenta")
        case .blue:
            return String(localized: "settings.subtitles.color.blue")
        case .cyan:
            return String(localized: "settings.subtitles.color.cyan")
        case .green:
            return String(localized: "settings.subtitles.color.green")
        case .black:
            return String(localized: "settings.subtitles.color.black")
        }
    }

    var codableColor: CodableColor {
        switch self {
        case .white:
            return CodableColor(red: 1, green: 1, blue: 1)
        case .yellow:
            return CodableColor(red: 1, green: 1, blue: 0)
        case .orange:
            return CodableColor(red: 1, green: 0.58, blue: 0)
        case .red:
            return CodableColor(red: 1, green: 0.23, blue: 0.19)
        case .magenta:
            return CodableColor(red: 1, green: 0.18, blue: 0.83)
        case .blue:
            return CodableColor(red: 0.04, green: 0.52, blue: 1)
        case .cyan:
            return CodableColor(red: 0.25, green: 0.78, blue: 0.98)
        case .green:
            return CodableColor(red: 0.16, green: 0.86, blue: 0.25)
        case .black:
            return CodableColor(red: 0, green: 0, blue: 0)
        }
    }

    /// The preset closest to the given color (ignoring opacity).
    static func nearest(to color: CodableColor) -> SubtitleColorPreset {
        allCases.min { lhs, rhs in
            distance(lhs.codableColor, color) < distance(rhs.codableColor, color)
        } ?? .white
    }

    private static func distance(_ a: CodableColor, _ b: CodableColor) -> Double {
        let dr = a.red - b.red
        let dg = a.green - b.green
        let db = a.blue - b.blue
        return dr * dr + dg * dg + db * db
    }
}
#endif

// MARK: - Preview

#Preview {
    NavigationStack {
        SubtitlesSettingsView()
    }
    .appEnvironment(.preview)
}
