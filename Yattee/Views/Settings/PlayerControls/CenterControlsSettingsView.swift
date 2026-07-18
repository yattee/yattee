//
//  CenterControlsSettingsView.swift
//  Yattee
//
//  View for configuring center section player controls.
//

import SwiftUI

/// View for configuring center section controls (play/pause, seek buttons).
struct CenterControlsSettingsView: View {
    @Bindable var viewModel: PlayerControlsSettingsViewModel

    // Local state that mirrors ViewModel - ensures immediate UI updates
    @State private var showPlayPause: Bool = true
    @State private var showSeekBackward: Bool = true
    @State private var showSeekForward: Bool = true
    @State private var seekBackwardSeconds: Double = 10
    @State private var seekForwardSeconds: Double = 10
    @State private var secondarySeekBackwardSeconds: Double = 30
    @State private var secondarySeekForwardSeconds: Double = 30
    @State private var leftSlider: SideSliderType = .disabled
    @State private var rightSlider: SideSliderType = .disabled

    /// On macOS the center overlay doesn't exist; the seek durations always
    /// apply (keyboard arrows and default seek buttons), so the controls are
    /// always visible there.
    private var seekBackwardControlsVisible: Bool {
        #if os(macOS)
        return true
        #else
        return showSeekBackward
        #endif
    }

    private var seekForwardControlsVisible: Bool {
        #if os(macOS)
        return true
        #else
        return showSeekForward
        #endif
    }

    var body: some View {
        Form {
            #if os(iOS)
            // Preview
            Section {
                CenterPreviewView(
                    settings: previewSettings,
                    buttonBackground: viewModel.currentLayout.globalSettings.buttonBackground,
                    theme: viewModel.currentLayout.globalSettings.theme
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } header: {
                Text(String(localized: "settings.playerControls.preview"))
            }

            // Play/Pause toggle
            Section {
                Toggle(
                    String(localized: "settings.playerControls.center.showPlayPause"),
                    isOn: $showPlayPause
                )
                .onChange(of: showPlayPause) { _, newValue in
                    viewModel.updateCenterSettingsSync { $0.showPlayPause = newValue }
                }
            } header: {
                Text(String(localized: "settings.playerControls.center.playback"))
            }
            #endif

            // Seek backward settings
            Section {
                #if os(iOS)
                Toggle(
                    String(localized: "settings.playerControls.center.showSeekBackward"),
                    isOn: $showSeekBackward
                )
                .onChange(of: showSeekBackward) { _, newValue in
                    viewModel.updateCenterSettingsSync { $0.showSeekBackward = newValue }
                }
                #endif

                if seekBackwardControlsVisible {
                    #if !os(tvOS)
                    HStack {
                        Text(String(localized: "settings.playerControls.center.seekBackwardTime"))
                        Spacer()
                        Text("\(Int(seekBackwardSeconds))s")
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: $seekBackwardSeconds,
                        in: 1...90,
                        step: 1
                    )
                    .onChange(of: seekBackwardSeconds) { _, newValue in
                        viewModel.updateCenterSettingsSync { $0.seekBackwardSeconds = Int(newValue) }
                    }
                    #endif

                    // Quick presets
                    HStack(spacing: 8) {
                        ForEach([5, 10, 15, 30, 45, 60], id: \.self) { seconds in
                            Button("\(seconds)s") {
                                seekBackwardSeconds = Double(seconds)
                            }
                            .buttonStyle(.bordered)
                            #if !os(tvOS)
                            .controlSize(.small)
                            #endif
                            .tint(Int(seekBackwardSeconds) == seconds ? .accentColor : .secondary)
                        }
                    }

                    #if os(macOS)
                    HStack {
                        Text(String(
                            localized: "settings.playerControls.center.secondarySeekBackwardTime",
                            defaultValue: "Secondary Seek Time"
                        ))
                        Spacer()
                        Text("\(Int(secondarySeekBackwardSeconds))s")
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: $secondarySeekBackwardSeconds,
                        in: 1...90,
                        step: 1
                    )
                    .onChange(of: secondarySeekBackwardSeconds) { _, newValue in
                        viewModel.updateCenterSettingsSync { $0.secondarySeekBackwardSeconds = Int(newValue) }
                    }

                    // Quick presets
                    HStack(spacing: 8) {
                        ForEach([15, 30, 45, 60, 90], id: \.self) { seconds in
                            Button("\(seconds)s") {
                                secondarySeekBackwardSeconds = Double(seconds)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(Int(secondarySeekBackwardSeconds) == seconds ? .accentColor : .secondary)
                        }
                    }
                    #endif
                }
            } header: {
                Text(String(localized: "settings.playerControls.center.seekBackward"))
            }

            // Seek forward settings
            Section {
                #if os(iOS)
                Toggle(
                    String(localized: "settings.playerControls.center.showSeekForward"),
                    isOn: $showSeekForward
                )
                .onChange(of: showSeekForward) { _, newValue in
                    viewModel.updateCenterSettingsSync { $0.showSeekForward = newValue }
                }
                #endif

                if seekForwardControlsVisible {
                    #if !os(tvOS)
                    HStack {
                        Text(String(localized: "settings.playerControls.center.seekForwardTime"))
                        Spacer()
                        Text("\(Int(seekForwardSeconds))s")
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: $seekForwardSeconds,
                        in: 1...90,
                        step: 1
                    )
                    .onChange(of: seekForwardSeconds) { _, newValue in
                        viewModel.updateCenterSettingsSync { $0.seekForwardSeconds = Int(newValue) }
                    }
                    #endif

                    // Quick presets
                    HStack(spacing: 8) {
                        ForEach([5, 10, 15, 30, 45, 60], id: \.self) { seconds in
                            Button("\(seconds)s") {
                                seekForwardSeconds = Double(seconds)
                            }
                            .buttonStyle(.bordered)
                            #if !os(tvOS)
                            .controlSize(.small)
                            #endif
                            .tint(Int(seekForwardSeconds) == seconds ? .accentColor : .secondary)
                        }
                    }

                    #if os(macOS)
                    HStack {
                        Text(String(
                            localized: "settings.playerControls.center.secondarySeekForwardTime",
                            defaultValue: "Secondary Seek Time"
                        ))
                        Spacer()
                        Text("\(Int(secondarySeekForwardSeconds))s")
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: $secondarySeekForwardSeconds,
                        in: 1...90,
                        step: 1
                    )
                    .onChange(of: secondarySeekForwardSeconds) { _, newValue in
                        viewModel.updateCenterSettingsSync { $0.secondarySeekForwardSeconds = Int(newValue) }
                    }

                    // Quick presets
                    HStack(spacing: 8) {
                        ForEach([15, 30, 45, 60, 90], id: \.self) { seconds in
                            Button("\(seconds)s") {
                                secondarySeekForwardSeconds = Double(seconds)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(Int(secondarySeekForwardSeconds) == seconds ? .accentColor : .secondary)
                        }
                    }
                    #endif
                }
            } header: {
                Text(String(localized: "settings.playerControls.center.seekForward"))
            } footer: {
                #if os(macOS)
                Text(String(
                    localized: "settings.playerControls.center.seekDurationsFooter",
                    defaultValue: "Seek durations are used by the ← and → keyboard shortcuts and by seek buttons added to the player. Hold ⇧ Shift with ← or → to seek by the secondary durations."
                ))
                #endif
            }

            #if os(iOS)
            // Side sliders section (iOS only)
            Section {
                Picker(
                    String(localized: "settings.playerControls.center.leftSlider"),
                    selection: $leftSlider
                ) {
                    ForEach(SideSliderType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .onChange(of: leftSlider) { _, newValue in
                    viewModel.updateCenterSettingsSync { $0.leftSlider = newValue }
                }

                Picker(
                    String(localized: "settings.playerControls.center.rightSlider"),
                    selection: $rightSlider
                ) {
                    ForEach(SideSliderType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .onChange(of: rightSlider) { _, newValue in
                    viewModel.updateCenterSettingsSync { $0.rightSlider = newValue }
                }
            } header: {
                Text(String(localized: "settings.playerControls.center.sliders"))
            } footer: {
                Text(String(localized: "settings.playerControls.center.slidersFooter"))
            }
            #endif
        }
        #if os(macOS)
        .formStyle(.grouped)
        .navigationTitle(String(localized: "settings.playerControls.seekDurations", defaultValue: "Seek Durations"))
        #else
        .navigationTitle(String(localized: "settings.playerControls.centerControls"))
        #endif
        .opaqueSettingsFormBackground()
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            syncFromViewModel()
        }
    }

    // MARK: - Computed Properties

    /// Settings for preview - uses local state for immediate updates
    private var previewSettings: CenterSectionSettings {
        CenterSectionSettings(
            showPlayPause: showPlayPause,
            showSeekBackward: showSeekBackward,
            showSeekForward: showSeekForward,
            seekBackwardSeconds: Int(seekBackwardSeconds),
            seekForwardSeconds: Int(seekForwardSeconds),
            secondarySeekBackwardSeconds: Int(secondarySeekBackwardSeconds),
            secondarySeekForwardSeconds: Int(secondarySeekForwardSeconds),
            leftSlider: leftSlider,
            rightSlider: rightSlider
        )
    }

    // MARK: - Helpers

    /// Syncs local state from ViewModel
    private func syncFromViewModel() {
        let settings = viewModel.centerSettings
        showPlayPause = settings.showPlayPause
        showSeekBackward = settings.showSeekBackward
        showSeekForward = settings.showSeekForward
        seekBackwardSeconds = Double(settings.seekBackwardSeconds)
        seekForwardSeconds = Double(settings.seekForwardSeconds)
        secondarySeekBackwardSeconds = Double(settings.secondarySeekBackwardSeconds)
        secondarySeekForwardSeconds = Double(settings.secondarySeekForwardSeconds)
        leftSlider = settings.leftSlider
        rightSlider = settings.rightSlider
    }
}

// MARK: - Center Preview

#if os(iOS)
/// Preview representation of a vertical side slider.
private struct SliderPreview: View {
    let type: SideSliderType
    let buttonBackground: ButtonBackgroundStyle

    var body: some View {
        VStack(spacing: 4) {
            if let icon = type.systemImage {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
            }

            // Slider track preview
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(.white.opacity(0.3))
                Capsule()
                    .fill(.white)
                    .frame(height: 30) // ~50% fill for preview
            }
            .frame(width: 3, height: 60)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(width: 24)
        .modifier(SliderPreviewBackgroundModifier(buttonBackground: buttonBackground))
    }
}

/// Applies background to slider preview based on button background style.
private struct SliderPreviewBackgroundModifier: ViewModifier {
    let buttonBackground: ButtonBackgroundStyle

    func body(content: Content) -> some View {
        if let glassStyle = buttonBackground.glassStyle {
            content.glassBackground(glassStyle, in: .capsule, fallback: .ultraThinMaterial)
        } else {
            content.background(.ultraThinMaterial.opacity(0.5), in: Capsule())
        }
    }
}
#endif

private struct CenterPreviewView: View {
    let settings: CenterSectionSettings
    let buttonBackground: ButtonBackgroundStyle
    let theme: ControlsTheme

    private let buttonSize: CGFloat = 32
    private let playButtonSize: CGFloat = 44
    private let spacing: CGFloat = 24

    var body: some View {
        ZStack {
            Image("PlayerControlsPreviewBackground")
                .resizable()
                .scaledToFill()

            // Gradient shade like actual player
            LinearGradient(
                colors: [.black.opacity(0.7), .clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Center controls
            HStack(spacing: spacing) {
                if settings.showSeekBackward {
                    CenterButtonPreview(
                        systemImage: settings.seekBackwardSystemImage,
                        size: buttonSize,
                        buttonBackground: buttonBackground
                    )
                }

                if settings.showPlayPause {
                    CenterButtonPreview(
                        systemImage: "play.fill",
                        size: playButtonSize,
                        buttonBackground: buttonBackground
                    )
                }

                if settings.showSeekForward {
                    CenterButtonPreview(
                        systemImage: settings.seekForwardSystemImage,
                        size: buttonSize,
                        buttonBackground: buttonBackground
                    )
                }
            }

            #if os(iOS)
            // Side sliders preview
            HStack {
                if settings.leftSlider != .disabled {
                    SliderPreview(type: settings.leftSlider, buttonBackground: buttonBackground)
                        .padding(.leading, 8)
                }
                Spacer()
                if settings.rightSlider != .disabled {
                    SliderPreview(type: settings.rightSlider, buttonBackground: buttonBackground)
                        .padding(.trailing, 8)
                }
            }
            #endif
        }
        .frame(height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
        .padding(.vertical, 8)
        .modifier(PreviewThemeModifier(theme: theme))
    }
}

private struct CenterButtonPreview: View {
    let systemImage: String
    let size: CGFloat
    let buttonBackground: ButtonBackgroundStyle

    /// Frame size - slightly larger when backgrounds are enabled.
    private var frameSize: CGFloat {
        buttonBackground.glassStyle != nil ? size * 1.4 : size * 1.2
    }

    var body: some View {
        if let glassStyle = buttonBackground.glassStyle {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.7))
                .foregroundStyle(.white)
                .frame(width: frameSize, height: frameSize)
                .glassBackground(glassStyle, in: .circle, fallback: .ultraThinMaterial)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.7))
                .foregroundStyle(.white)
                .frame(width: frameSize, height: frameSize)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CenterControlsSettingsView(
            viewModel: PlayerControlsSettingsViewModel(
                layoutService: PlayerControlsLayoutService(),
                settingsManager: SettingsManager()
            )
        )
    }
}
