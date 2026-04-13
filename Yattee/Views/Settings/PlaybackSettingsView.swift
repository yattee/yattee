//
//  PlaybackSettingsView.swift
//  Yattee
//
//  Playback settings view with quality and behavior preferences.
//

import SwiftUI

struct PlaybackSettingsView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        Form {
            if let settings = appEnvironment?.settingsManager {
                QualitySection(settings: settings)
                AudioSection(settings: settings)
                SubtitlesSection(settings: settings)
                BehaviorSection(settings: settings)
                QueueSection(settings: settings)
                #if os(iOS)
                OrientationSection(settings: settings)
                #endif
                #if os(macOS)
                MacOSSection(settings: settings)
                #endif
            }
        }
        #if !os(tvOS)
        .navigationTitle(String(localized: "settings.playback.title"))
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Quality Section

private struct QualitySection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        Section {
            Picker(
                String(localized: "settings.playback.quality.preferred"),
                selection: $settings.preferredQuality
            ) {
                ForEach(VideoQuality.allCases, id: \.self) { quality in
                    Text(quality.displayName).tag(quality)
                }
            }

            #if os(iOS)
            Picker(
                String(localized: "settings.playback.quality.cellular"),
                selection: $settings.cellularQuality
            ) {
                ForEach(VideoQuality.allCases, id: \.self) { quality in
                    Text(quality.displayName).tag(quality)
                }
            }
            #endif
        } header: {
            Text(String(localized: "settings.playback.video.header"))
        }
    }
}

// MARK: - Audio Section

private struct AudioSection: View {
    @Bindable var settings: SettingsManager

    // All YouTube-supported language codes, sorted alphabetically by localized name
    static let languageCodes: [String] = [
        "af", // Afrikaans
        "am", // Amharic
        "ar", // Arabic
        "az", // Azerbaijani
        "be", // Belarusian
        "bg", // Bulgarian
        "bn", // Bengali
        "bs", // Bosnian
        "ca", // Catalan
        "cs", // Czech
        "cy", // Welsh
        "da", // Danish
        "de", // German
        "el", // Greek
        "en", // English
        "es", // Spanish
        "et", // Estonian
        "eu", // Basque
        "fa", // Persian
        "fi", // Finnish
        "fil", // Filipino
        "fr", // French
        "gl", // Galician
        "gu", // Gujarati
        "he", // Hebrew
        "hi", // Hindi
        "hr", // Croatian
        "hu", // Hungarian
        "hy", // Armenian
        "id", // Indonesian
        "is", // Icelandic
        "it", // Italian
        "ja", // Japanese
        "ka", // Georgian
        "kk", // Kazakh
        "km", // Khmer
        "kn", // Kannada
        "ko", // Korean
        "ky", // Kyrgyz
        "lo", // Lao
        "lt", // Lithuanian
        "lv", // Latvian
        "mk", // Macedonian
        "ml", // Malayalam
        "mn", // Mongolian
        "mr", // Marathi
        "ms", // Malay
        "my", // Burmese
        "ne", // Nepali
        "nl", // Dutch
        "no", // Norwegian
        "or", // Odia
        "pa", // Punjabi
        "pl", // Polish
        "pt", // Portuguese
        "ro", // Romanian
        "ru", // Russian
        "si", // Sinhala
        "sk", // Slovak
        "sl", // Slovenian
        "sq", // Albanian
        "sr", // Serbian
        "sv", // Swedish
        "sw", // Swahili
        "ta", // Tamil
        "te", // Telugu
        "th", // Thai
        "tr", // Turkish
        "uk", // Ukrainian
        "ur", // Urdu
        "uz", // Uzbek
        "vi", // Vietnamese
        "zh", // Chinese
        "zu", // Zulu
    ]

    // Generate sorted list of (code, localizedName) tuples
    private var sortedLanguages: [(code: String, name: String)] {
        Self.languageCodes
            .map { code in
                let name = Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
                return (code: code, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Section {
            Picker(
                String(localized: "settings.playback.audio.preferredLanguage"),
                selection: Binding(
                    get: { settings.preferredAudioLanguage ?? "" },
                    set: { settings.preferredAudioLanguage = $0.isEmpty ? nil : $0 }
                )
            ) {
                Text(String(localized: "settings.playback.audio.original"))
                    .tag("")

                Divider()

                ForEach(sortedLanguages, id: \.code) { language in
                    Text(language.name).tag(language.code)
                }
            }
        } header: {
            Text(String(localized: "settings.playback.audio.header"))
        }
    }
}

// Volume and System Controls settings are in Player Controls settings

// MARK: - Subtitles Section

private struct SubtitlesSection: View {
    @Bindable var settings: SettingsManager

    // Same language codes as audio
    private static let languageCodes = AudioSection.languageCodes

    // Generate sorted list of (code, localizedName) tuples
    private var sortedLanguages: [(code: String, name: String)] {
        Self.languageCodes
            .map { code in
                let name = Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
                return (code: code, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Section {
            Picker(
                String(localized: "settings.playback.subtitles.preferredLanguage"),
                selection: Binding(
                    get: { settings.preferredSubtitlesLanguage ?? "" },
                    set: { settings.preferredSubtitlesLanguage = $0.isEmpty ? nil : $0 }
                )
            ) {
                Text(String(localized: "settings.playback.subtitles.off"))
                    .tag("")

                Divider()

                ForEach(sortedLanguages, id: \.code) { language in
                    Text(language.name).tag(language.code)
                }
            }

            NavigationLink {
                SubtitlesSettingsView()
            } label: {
                Label(String(localized: "settings.playback.subtitles.appearance"), systemImage: "textformat.size")
            }
        } header: {
            Text(String(localized: "settings.playback.subtitles.header"))
        }
    }
}

// MARK: - Behavior Section

private struct BehaviorSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        Section(String(localized: "settings.playback.behavior.header")) {
            Picker(
                String(localized: "settings.playback.resumeAction"),
                selection: $settings.resumeAction
            ) {
                ForEach(ResumeAction.allCases, id: \.self) { action in
                    Text(action.displayName).tag(action)
                }
            }

            #if os(iOS) || os(macOS)
            Toggle(
                String(localized: "settings.playback.backgroundPlayback"),
                isOn: $settings.backgroundPlaybackEnabled
            )
            #endif
        }
    }
}

// MARK: - Queue Section

private struct QueueSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        Section {
            Toggle(
                String(localized: "settings.playback.queue.enabled"),
                isOn: $settings.queueEnabled
            )

            #if os(tvOS)
            Picker(
                String(localized: "settings.playback.queue.autoPlayCountdown"),
                selection: $settings.queueAutoPlayCountdown
            ) {
                ForEach(1...15, id: \.self) { value in
                    Text("\(value)s").tag(value)
                }
            }
            .disabled(!settings.queueEnabled)
            #elseif os(macOS)
            // macOS: Use simple string label (custom HStack label breaks Form rendering)
            Stepper(
                "\(String(localized: "settings.playback.queue.autoPlayCountdown")): \(settings.queueAutoPlayCountdown)s",
                value: $settings.queueAutoPlayCountdown,
                in: 1...15
            )
            .disabled(!settings.queueEnabled)
            #else
            Stepper(
                value: $settings.queueAutoPlayCountdown,
                in: 1...15
            ) {
                HStack {
                    Text(String(localized: "settings.playback.queue.autoPlayCountdown"))
                    Spacer()
                    Text("\(settings.queueAutoPlayCountdown)s")
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!settings.queueEnabled)
            #endif


        } header: {
            Text(String(localized: "settings.playback.queue.header"))
        } footer: {
            Text(String(localized: "settings.playback.queue.footer"))
        }
    }
}

// MARK: - Orientation Section (iOS)

#if os(iOS)
private struct OrientationSection: View {
    @Bindable var settings: SettingsManager

    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    var body: some View {
        Section {
            Toggle(
                String(localized: "settings.playback.orientation.rotateToMatchAspectRatio"),
                isOn: $settings.rotateToMatchAspectRatio
            )

            if isPhone {
                Toggle(
                    String(localized: "settings.playback.orientation.preferPortraitBrowsing"),
                    isOn: $settings.preferPortraitBrowsing
                )
            }
        } header: {
            Text(String(localized: "settings.playback.orientation.header"))
        }
    }
}
#endif

// MARK: - macOS Section

#if os(macOS)
private struct MacOSSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        Section(String(localized: "settings.playback.macOS.header")) {
            Picker(
                String(localized: "settings.playback.macOS.playerMode"),
                selection: $settings.macPlayerMode
            ) {
                ForEach(MacPlayerMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Toggle(
                String(localized: "settings.playback.macOS.autoResizePlayer"),
                isOn: $settings.playerSheetAutoResize
            )
        }
    }
}
#endif

// MARK: - VideoQuality Extension

extension VideoQuality {
    var displayName: String {
        switch self {
        case .auto: return String(localized: "settings.playback.quality.best")
        case .hd4k: return "4K"
        case .hd1440p: return "1440p"
        case .hd1080p: return "1080p"
        case .hd720p: return "720p"
        case .sd480p: return "480p"
        case .sd360p: return "360p"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PlaybackSettingsView()
    }
    .appEnvironment(.preview)
}
