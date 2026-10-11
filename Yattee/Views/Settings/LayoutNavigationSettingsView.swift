//
//  LayoutNavigationSettingsView.swift
//  Yattee
//
//  Settings view for layout and navigation customization.
//

import SwiftUI

struct LayoutNavigationSettingsView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        SettingsFormContainer {
            if let settings = appEnvironment?.settingsManager {
                CustomizationSection(settings: settings)
                #if os(iOS)
                HapticsSection(settings: settings)
                #endif
                #if os(tvOS)
                TVVideoActionsSection(settings: settings)
                #else
                VideoActionsSection(settings: settings)
                VideoInfoActionsSection(settings: settings)
                LinkActionSection(settings: settings)
                SharingSection(settings: settings)
                ClipboardSection(settings: settings)
                #endif
                #if os(iOS)
                if #available(iOS 26, *) {
                    MiniPlayerMinimizeBehaviorSection(settings: settings)
                }
                #endif
                #if !os(tvOS)
                HandoffSection(settings: settings)
                #endif
            }
        }
        #if !os(tvOS)
        .navigationTitle(String(localized: "settings.layoutNavigation.title"))
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Haptics Section

#if os(iOS)
private struct HapticsSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        if SettingsManager.deviceSupportsHaptics {
            SettingsFormSection {
                Toggle(
                    String(localized: "settings.haptics.title"),
                    isOn: $settings.hapticFeedbackEnabled
                )

                if settings.hapticFeedbackEnabled {
                    Picker(
                        String(localized: "settings.haptics.intensity"),
                        selection: $settings.hapticFeedbackIntensity
                    ) {
                        ForEach(HapticFeedbackIntensity.allCases.filter { $0 != .off }, id: \.self) { intensity in
                            Text(intensity.displayName).tag(intensity)
                        }
                    }
                }
            }
        }
    }
}
#endif

// MARK: - Customization Section

private struct CustomizationSection: View {
    @Bindable var settings: SettingsManager

    #if os(iOS)
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var hasHinge = HingeLayoutObserver.forceTabletop
    /// Style picked but not yet confirmed: switching rebuilds the navigation
    /// Settings lives in, so the user agrees to leaving it first.
    @State private var pendingNavigationStyle: NavigationStyle?
    #endif

    /// iPad and foldable iPhones (inner screen): where the sidebar layout can appear.
    private var canUseSidebar: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad || hasHinge
        #else
        true
        #endif
    }

    var body: some View {
        #if os(iOS)
        if canUseSidebar {
            SettingsFormSection(footer: "settings.navigationStyle.footer") {
                Picker(
                    String(localized: "settings.navigationStyle"),
                    selection: Binding(
                        get: { settings.navigationStyle },
                        set: { style in
                            guard style != settings.navigationStyle else { return }
                            pendingNavigationStyle = style
                        }
                    )
                ) {
                    ForEach(NavigationStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
            }
            .alert(
                String(localized: "settings.navigationStyle.confirm.title"),
                isPresented: Binding(
                    get: { pendingNavigationStyle != nil },
                    set: { if !$0 { pendingNavigationStyle = nil } }
                ),
                presenting: pendingNavigationStyle
            ) { style in
                Button(String(localized: "settings.navigationStyle.confirm.change")) {
                    applyNavigationStyle(style)
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: { _ in
                Text(String(localized: "settings.navigationStyle.confirm.message"))
            }
        }
        #endif

        SettingsFormSection {
            #if os(tvOS)
            NavigationLink {
                TVSidebarDetailContainer(
                    systemImage: SidebarItem.home.systemImage,
                    title: String(localized: "settings.appearance.home.customize")
                ) { HomeSettingsView() }
            } label: {
                Label(String(localized: "settings.appearance.home.customize"), systemImage: SidebarItem.home.systemImage)
            }
            #else
            SettingsNavigationRow("settings.appearance.home.customize", systemImage: SidebarItem.home.systemImage) {
                HomeSettingsView()
            }
            #endif

            #if os(iOS)
            SettingsNavigationRow("settings.tabBar.title", systemImage: "square.grid.3x3") {
                TabBarSettingsView()
            }

            if canUseSidebar && settings.navigationStyle == .automatic {
                SettingsNavigationRow("settings.sidebar.title", systemImage: "sidebar.leading") {
                    SidebarSettingsView()
                }
            }
            #endif

            #if os(macOS)
            SettingsNavigationRow("settings.sidebar.title", systemImage: "sidebar.leading") {
                SidebarSettingsView()
            }
            #elseif os(tvOS)
            NavigationLink {
                TVSidebarDetailContainer(
                    systemImage: "sidebar.leading",
                    title: String(localized: "settings.sidebar.title")
                ) { SidebarSettingsView() }
            } label: {
                Label(String(localized: "settings.sidebar.title"), systemImage: "sidebar.leading")
            }
            #endif
        }
        #if os(iOS)
        .observeHinge(hasHinge: $hasHinge)
        #endif
    }

    #if os(iOS)
    /// Lands on Home before the layout swap, so neither layout remaps the
    /// Settings selection (the tab bar would reopen it as a sheet).
    private func applyNavigationStyle(_ style: NavigationStyle) {
        if let router = appEnvironment?.navigationCoordinator.router {
            router.popToRoot(router.selection)
            router.selection = .home
        }
        settings.navigationStyle = style
    }
    #endif
}

// MARK: - Link Action Section

private struct LinkActionSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        SettingsFormSection("settings.behavior.linkAction.header", footer: "settings.behavior.linkAction.footer") {
            Picker(
                String(localized: "settings.behavior.linkAction"),
                selection: $settings.defaultLinkAction
            ) {
                ForEach(DefaultLinkAction.allCases, id: \.self) { action in
                    Text(action.displayName).tag(action)
                }
            }
        }

        SettingsFormSection(footer: "settings.behavior.linkActionsWithoutConfirmation.footer") {
            Toggle(
                String(localized: "settings.behavior.linkActionsWithoutConfirmation"),
                isOn: $settings.linkActionsRunWithoutConfirmation
            )
        }
    }
}

// MARK: - Sharing Section

#if !os(tvOS)
private struct SharingSection: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Bindable var settings: SettingsManager

    /// Shown only when a source with a web watch page exists — without one
    /// the toggle can't change anything.
    private var hasPrivacyFrontendSource: Bool {
        appEnvironment?.instancesManager.enabledInstances.contains { $0.watchPageBaseURL != nil } ?? false
    }

    var body: some View {
        if hasPrivacyFrontendSource {
            SettingsFormSection("settings.behavior.sharing.header", footer: "settings.behavior.privacyFrontendSharing.footer") {
                Toggle(
                    String(localized: "settings.behavior.privacyFrontendSharing"),
                    isOn: $settings.privacyFrontendSharingEnabled
                )
            }
        }
    }
}
#endif

// MARK: - Clipboard Section

private struct ClipboardSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        SettingsFormSection("settings.dataPrivacy.clipboard.header", footer: "settings.behavior.clipboardMonitoring.footer") {
            Toggle(
                String(localized: "settings.behavior.clipboardMonitoring"),
                isOn: $settings.clipboardURLDetectionEnabled
            )
        }
    }
}

// MARK: - Video Actions Section

#if !os(tvOS)
private struct VideoActionsSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        SettingsFormSection("settings.videoActions.header") {
            Picker(
                String(localized: "settings.behavior.thumbnailTapAction"),
                selection: $settings.thumbnailTapAction
            ) {
                ForEach(VideoTapAction.allCases, id: \.self) { action in
                    Text(action.displayName).tag(action)
                }
            }

            Picker(
                String(localized: "settings.behavior.textAreaTapAction"),
                selection: $settings.textAreaTapAction
            ) {
                ForEach(VideoTapAction.allCases, id: \.self) { action in
                    Text(action.displayName).tag(action)
                }
            }

            #if os(iOS)
            NavigationLink {
                SwipeActionsSettingsView()
            } label: {
                Label(String(localized: "settings.appearance.swipeActions"), systemImage: "hand.draw")
            }
            #endif
        }
    }
}
#endif

// MARK: - Video Info Actions Section

#if !os(tvOS)
private struct VideoInfoActionsSection: View {
    @Bindable var settings: SettingsManager

    /// macOS shows every action in the toolbar; iOS pins one and tucks the rest into the ⋯ menu.
    private var actionsFooter: LocalizedStringKey {
        #if os(macOS)
        "settings.videoInfo.actions.footer.macOS"
        #else
        "settings.videoInfo.actions.footer"
        #endif
    }

    var body: some View {
        SettingsFormSection("settings.videoInfo.actions.header", footer: actionsFooter) {
            Picker(
                String(localized: "settings.videoInfo.actionsLayout"),
                selection: $settings.videoInfoActionsLayout
            ) {
                ForEach(VideoInfoActionsLayout.allCases, id: \.self) { layout in
                    Text(layout.displayName).tag(layout)
                }
            }

            #if os(iOS)
            if settings.videoInfoActionsLayout == .toolbar {
                Picker(
                    String(localized: "settings.videoInfo.primaryAction"),
                    selection: $settings.videoInfoPrimaryAction
                ) {
                    ForEach(VideoInfoPrimaryAction.allCases, id: \.self) { action in
                        Text(action.displayName).tag(action)
                    }
                }
            }
            #endif
        }
    }
}
#endif

// MARK: - TV Video Actions Section

#if os(tvOS)
private struct TVVideoActionsSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        SettingsFormSection("settings.videoActions.header") {
            LabeledContent(String(localized: "settings.behavior.tvOSVideoTapAction")) {
                Picker(
                    String(localized: "settings.behavior.tvOSVideoTapAction"),
                    selection: $settings.tvOSVideoTapAction
                ) {
                    Text(VideoTapAction.openInfo.displayName).tag(VideoTapAction.openInfo)
                    Text(VideoTapAction.playVideo.displayName).tag(VideoTapAction.playVideo)
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }
}
#endif

// MARK: - Mini Player Minimize Behavior Section (iOS 26+)

#if os(iOS)
@available(iOS 26, *)
private struct MiniPlayerMinimizeBehaviorSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        SettingsFormSection("settings.behavior.miniPlayer.header", footer: "settings.behavior.miniPlayer.minimizeBehavior.footer") {
            Picker(
                String(localized: "settings.behavior.miniPlayer.minimizeBehavior"),
                selection: $settings.miniPlayerMinimizeBehavior
            ) {
                ForEach(MiniPlayerMinimizeBehavior.allCases, id: \.self) { behavior in
                    Text(behavior.displayName).tag(behavior)
                }
            }
        }
    }
}
#endif

// MARK: - Handoff Section

private struct HandoffSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        SettingsFormSection("settings.behavior.handoff.header", footer: "settings.behavior.handoff.footer") {
            Toggle(
                String(localized: "settings.behavior.handoff"),
                isOn: $settings.handoffEnabled
            )
        }
    }
}

#Preview {
    NavigationStack {
        LayoutNavigationSettingsView()
    }
    .appEnvironment(.preview)
}
