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
        Form {
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
        Section {
            Picker(
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
            Picker(String(localized: "settings.subtitles.fontSize"), selection: $settings.fontSize) {
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
        Section {
            #if os(tvOS)
            HStack {
                Text(String(localized: "settings.subtitles.textColor"))
                Spacer()
                Circle()
                    .fill(settings.textColor.color)
                    .frame(width: 24, height: 24)
            }

            HStack {
                Text(String(localized: "settings.subtitles.borderColor"))
                Spacer()
                Circle()
                    .fill(settings.borderColor.color)
                    .frame(width: 24, height: 24)
            }

            LabeledContent(
                String(localized: "settings.subtitles.borderSize"),
                value: String(format: "%.1f", settings.borderSize)
            )
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
                HStack {
                    Text(String(localized: "settings.subtitles.backgroundColor"))
                    Spacer()
                    Circle()
                        .fill(settings.backgroundColor.color)
                        .frame(width: 24, height: 24)
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
        } header: {
            Text(String(localized: "settings.subtitles.colorsSection"))
        }
    }

    // MARK: - Style Section

    private var styleSection: some View {
        Section {
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
        } header: {
            Text(String(localized: "settings.subtitles.styleSection"))
        }
    }

    // MARK: - Position Section

    private var positionSection: some View {
        Section {
            #if os(tvOS)
            LabeledContent(
                String(localized: "settings.subtitles.positionSection"),
                value: "\(settings.bottomMargin)"
            )
            #else
            Stepper(
                String(localized: "settings.subtitles.bottomMargin \(settings.bottomMargin)"),
                value: $settings.bottomMargin,
                in: 0...50,
                step: 5
            )
            .onChange(of: settings.bottomMargin) { _, _ in saveSettings() }
            #endif
        } header: {
            Text(String(localized: "settings.subtitles.positionSection"))
        } footer: {
            Text(String(localized: "settings.subtitles.positionFooter"))
        }
    }

    // MARK: - Reset Section

    private var resetSection: some View {
        Section {
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

    // MARK: - Helpers

    private func saveSettings() {
        appEnvironment?.settingsManager.subtitleSettings = settings

        // Apply changes to active MPV player immediately
        if let mpvBackend = appEnvironment?.playerService.currentBackend as? MPVBackend {
            mpvBackend.updateSubtitleSettings()
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SubtitlesSettingsView()
    }
    .appEnvironment(.preview)
}
