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
                CustomizationSection()
                #if os(iOS)
                HapticsSection(settings: settings)
                #endif
                #if os(tvOS)
                TVVideoActionsSection(settings: settings)
                #else
                VideoActionsSection(settings: settings)
                LinkActionSection(settings: settings)
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
    var body: some View {
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

            // Sidebar settings only on iPad (not iPhone)
            if UIDevice.current.userInterfaceIdiom == .pad {
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
    }
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
    }
}

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
