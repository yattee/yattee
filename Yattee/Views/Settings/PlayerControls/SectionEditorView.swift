//
//  SectionEditorView.swift
//  Yattee
//
//  View for editing buttons in a player controls section (top or bottom).
//

import SwiftUI

/// View for editing buttons in a specific section of the player controls.
struct SectionEditorView: View {
    let sectionType: LayoutSectionType
    @Bindable var viewModel: PlayerControlsSettingsViewModel

    // Local state for immediate UI updates
    @State private var buttons: [ControlButtonConfiguration] = []
    @State private var availableTypes: [ControlButtonType] = []

    var body: some View {
        List {
            // Section preview
            SectionPreviewView(
                sectionType: sectionType,
                section: LayoutSection(buttons: buttons),
                isLandscape: viewModel.isPreviewingLandscape,
                fontStyle: viewModel.currentLayout.globalSettings.fontStyle,
                buttonBackground: viewModel.currentLayout.globalSettings.buttonBackground,
                theme: viewModel.currentLayout.globalSettings.theme
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            // Orientation toggle
            Picker(
                String(localized: "settings.playerControls.previewOrientation"),
                selection: $viewModel.isPreviewingLandscape
            ) {
                Text(String(localized: "settings.playerControls.portrait"))
                    .tag(false)
                Text(String(localized: "settings.playerControls.landscape"))
                    .tag(true)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            // Added buttons
            Section {
                ForEach(buttons) { button in
                    NavigationLink {
                        ButtonConfigurationView(
                            buttonID: button.id,
                            sectionType: sectionType,
                            viewModel: viewModel
                        )
                    } label: {
                        ButtonRow(configuration: button)
                    }
                }
                .onMove { source, destination in
                    // Update local state immediately
                    buttons.move(fromOffsets: source, toOffset: destination)
                    // Sync to view model
                    viewModel.moveButtonSync(
                        fromOffsets: source,
                        toOffset: destination,
                        in: sectionType
                    )
                }
                .onDelete { indexSet in
                    // Get button IDs before removing from local state
                    let buttonIDs = indexSet.map { buttons[$0].id }
                    // Update local state immediately
                    buttons.remove(atOffsets: indexSet)
                    // Sync to view model
                    for id in buttonIDs {
                        viewModel.removeButtonSync(id, from: sectionType)
                    }
                    // Update available types
                    syncAvailableTypes()
                }
            } header: {
                Text(String(localized: "settings.playerControls.addedButtons"))
            }

            // Available buttons
            Section {
                ForEach(availableTypes, id: \.self) { buttonType in
                    Button {
                        addButton(buttonType)
                    } label: {
                        HStack {
                            Image(systemName: buttonType.systemImage)
                                .frame(width: 24)
                                .foregroundStyle(.tint)

                            Text(buttonType.displayName)
                                .foregroundStyle(.primary)

                            Spacer()

                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(String(localized: "settings.playerControls.availableButtons"))
            } footer: {
                Text(String(localized: "settings.playerControls.availableButtonsFooter"))
            }
        }
        .navigationTitle(sectionTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            EditButton()
            #endif
        }
        .onAppear {
            syncFromViewModel()
        }
        .onChange(of: viewModel.activePreset?.layout) { _, _ in
            syncFromViewModel()
        }
    }

    // MARK: - Helpers

    private func syncFromViewModel() {
        guard let preset = viewModel.activePreset else { return }
        switch sectionType {
        case .top:
            buttons = preset.layout.topSection.buttons
        case .bottom:
            buttons = preset.layout.bottomSection.buttons
        }
        syncAvailableTypes()
    }

    private func syncAvailableTypes() {
        let usedTypes = Set(buttons.map(\.buttonType))
        availableTypes = ControlButtonType.availableForHorizontalSections.filter { buttonType in
            // Spacer can be added multiple times
            buttonType == .spacer || !usedTypes.contains(buttonType)
        }
    }

    private func addButton(_ buttonType: ControlButtonType) {
        // Create new config and add to local state immediately
        let config = ControlButtonConfiguration.defaultConfiguration(for: buttonType)
        buttons.append(config)
        // Update available types
        syncAvailableTypes()
        // Sync to view model
        viewModel.addButtonSync(buttonType, to: sectionType)
    }

    private var sectionTitle: String {
        switch sectionType {
        case .top:
            return String(localized: "settings.playerControls.topButtons")
        case .bottom:
            return String(localized: "settings.playerControls.bottomButtons")
        }
    }
}

// MARK: - Button Row

private struct ButtonRow: View {
    let configuration: ControlButtonConfiguration

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: configuration.buttonType.systemImage)
                .frame(width: 24)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(configuration.buttonType.displayName)

                if configuration.visibilityMode != .both {
                    Text(configuration.visibilityMode.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }
}

// MARK: - Section Preview

private struct SectionPreviewView: View {
    let sectionType: LayoutSectionType
    let section: LayoutSection
    let isLandscape: Bool
    let fontStyle: ControlsFontStyle
    let buttonBackground: ButtonBackgroundStyle
    let theme: ControlsTheme

    private let buttonSize: CGFloat = 20
    private let buttonSpacing: CGFloat = 8
    private let barHeight: CGFloat = 50

    var body: some View {
        GeometryReader { geometry in
            let containerWidth = geometry.size.width

            if isLandscape {
                // Landscape: use full container width, or scroll if content is wider
                ScrollView(.horizontal, showsIndicators: false) {
                    barContent(minWidth: containerWidth, height: barHeight)
                }
                .frame(height: barHeight)
            } else {
                // Portrait: full width horizontal bar
                barContent(minWidth: containerWidth, height: barHeight)
            }
        }
        .frame(height: barHeight)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .modifier(PreviewThemeModifier(theme: theme))
    }

    @ViewBuilder
    private func barContent(minWidth: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: buttonSpacing) {
            ForEach(section.visibleButtons(isWideLayout: isLandscape)) { button in
                PreviewButtonView(
                    configuration: button,
                    size: buttonSize,
                    isLandscape: isLandscape,
                    fontStyle: fontStyle,
                    buttonBackground: buttonBackground
                )
            }
        }
        .padding(.horizontal, 12)
        .frame(minWidth: minWidth, minHeight: height)
        .background(
            Image("PlayerControlsPreviewBackground")
                .resizable()
                .scaledToFill()
                .overlay {
                    LinearGradient(
                        colors: sectionType == .top
                            ? [.black.opacity(0.7), .clear]
                            : [.clear, .black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PreviewButtonView: View {
    let configuration: ControlButtonConfiguration
    let size: CGFloat
    let isLandscape: Bool
    let fontStyle: ControlsFontStyle
    let buttonBackground: ButtonBackgroundStyle

    /// Whether this button should show a glass background.
    private var hasBackground: Bool { buttonBackground.glassStyle != nil }

    /// Frame size - slightly larger when backgrounds are enabled.
    private var frameSize: CGFloat { hasBackground ? size * 1.7 : size * 1.5 }

    var body: some View {
        Group {
            if configuration.buttonType == .spacer {
                if let settings = configuration.settings,
                   case .spacer(let spacerSettings) = settings,
                   spacerSettings.isFlexible {
                    Spacer()
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: spacerWidth)
                }
            } else if configuration.buttonType == .timeDisplay {
                Text(verbatim: "0:00 / 3:45")
                    .font(fontStyle.font(size: size * 0.6, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            } else if configuration.buttonType == .brightness || configuration.buttonType == .volume {
                // Slider buttons - show based on behavior
                sliderPreview
            } else if configuration.buttonType == .seek {
                // Seek button - show dynamic icon based on settings
                seekButtonContent
            } else if configuration.buttonType == .titleAuthor {
                // Title/Author button - show preview matching actual layout
                titleAuthorPreview
            } else {
                // Regular button
                regularButtonContent
            }
        }
    }

    // MARK: - Seek Button Content

    @ViewBuilder
    private var seekButtonContent: some View {
        let seekSettings = configuration.seekSettings ?? SeekSettings()
        if let glassStyle = buttonBackground.glassStyle {
            Image(systemName: seekSettings.systemImage)
                .font(.system(size: size))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: frameSize, height: frameSize)
                .glassBackground(glassStyle, in: .circle, fallback: .ultraThinMaterial)
        } else {
            Image(systemName: seekSettings.systemImage)
                .font(.system(size: size))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: frameSize, height: frameSize)
        }
    }

    // MARK: - Title/Author Preview

    @ViewBuilder
    private var titleAuthorPreview: some View {
        let settings = configuration.titleAuthorSettings ?? TitleAuthorSettings()
        let avatarSize = size * 1.4

        HStack(spacing: 6) {
            // Avatar placeholder
            if settings.showSourceImage {
                Circle()
                    .fill(.white.opacity(0.3))
                    .frame(width: avatarSize, height: avatarSize)
                    .overlay {
                        Text(verbatim: "Y")
                            .font(.system(size: size * 0.7, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
            }

            // Title and author stack
            if settings.showTitle || settings.showSourceName {
                VStack(alignment: .leading, spacing: 1) {
                    if settings.showTitle {
                        Text(verbatim: "Video Title")
                            .font(fontStyle.font(size: size * 0.55, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }

                    if settings.showSourceName {
                        Text(verbatim: "Channel Name")
                            .font(fontStyle.font(size: size * 0.45))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, buttonBackground.glassStyle != nil ? 8 : 0)
        .padding(.vertical, buttonBackground.glassStyle != nil ? 4 : 0)
        .modifier(OptionalCapsuleGlassBackgroundModifier(style: buttonBackground))
    }

    // MARK: - Regular Button Content

    @ViewBuilder
    private var regularButtonContent: some View {
        if let glassStyle = buttonBackground.glassStyle {
            Image(systemName: configuration.buttonType.systemImage)
                .font(.system(size: size))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: frameSize, height: frameSize)
                .glassBackground(glassStyle, in: .circle, fallback: .ultraThinMaterial)
        } else {
            Image(systemName: configuration.buttonType.systemImage)
                .font(.system(size: size))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: frameSize, height: frameSize)
        }
    }

    // MARK: - Slider Preview

    @ViewBuilder
    private var sliderPreview: some View {
        let behavior = configuration.sliderSettings?.sliderBehavior ?? .expandOnTap

        // Compute effective behavior based on orientation for autoExpandInLandscape
        let effectiveBehavior: SliderBehavior = {
            if behavior == .autoExpandInLandscape {
                return isLandscape ? .alwaysVisible : .expandOnTap
            }
            return behavior
        }()

        HStack(spacing: 3) {
            // Icon with optional glass background
            sliderIconContent

            // Fake slider - show when effectively always visible
            if effectiveBehavior == .alwaysVisible {
                ZStack(alignment: .leading) {
                    // Slider track
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.white.opacity(0.3))
                        .frame(width: size * 3, height: 3)

                    // Slider fill (showing ~60% filled)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.white.opacity(0.8))
                        .frame(width: size * 1.8, height: 3)
                }
            }
        }
    }

    @ViewBuilder
    private var sliderIconContent: some View {
        let iconFrameSize = hasBackground ? size * 1.4 : size * 1.2
        if let glassStyle = buttonBackground.glassStyle {
            Image(systemName: configuration.buttonType.systemImage)
                .font(.system(size: size))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: iconFrameSize, height: iconFrameSize)
                .glassBackground(glassStyle, in: .circle, fallback: .ultraThinMaterial)
        } else {
            Image(systemName: configuration.buttonType.systemImage)
                .font(.system(size: size))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: iconFrameSize, height: iconFrameSize)
        }
    }

    private var spacerWidth: CGFloat {
        guard let settings = configuration.settings,
              case .spacer(let spacerSettings) = settings else {
            return 8
        }
        return CGFloat(spacerSettings.fixedWidth) / 4
    }
}

// MARK: - Optional Capsule Glass Background Modifier

/// A view modifier that conditionally applies a capsule glass background.
private struct OptionalCapsuleGlassBackgroundModifier: ViewModifier {
    let style: ButtonBackgroundStyle

    func body(content: Content) -> some View {
        if let glassStyle = style.glassStyle {
            content.glassBackground(glassStyle, in: .capsule, fallback: .ultraThinMaterial)
        } else {
            content
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SectionEditorView(
            sectionType: .top,
            viewModel: PlayerControlsSettingsViewModel(
                layoutService: PlayerControlsLayoutService(),
                settingsManager: SettingsManager()
            )
        )
    }
}
