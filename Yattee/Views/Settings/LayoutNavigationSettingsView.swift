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
        Form {
            if let settings = appEnvironment?.settingsManager {
                CustomizationSection()
                #if os(iOS)
                HapticsSection(settings: settings)
                #endif
                #if !os(tvOS)
                VideoActionsSection(settings: settings)
                #endif
                LinkActionSection(settings: settings)
                ClipboardSection(settings: settings)
                #if os(iOS)
                if #available(iOS 26, *) {
                    MiniPlayerMinimizeBehaviorSection(settings: settings)
                }
                #endif
                HandoffSection(settings: settings)
            }
        }
        .navigationTitle(String(localized: "settings.layoutNavigation.title"))
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
            Section {
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
        Section {
            NavigationLink {
                HomeSettingsView()
            } label: {
                Label(String(localized: "settings.appearance.home.customize"), systemImage: SidebarItem.home.systemImage)
            }

            #if os(iOS)
            NavigationLink {
                TabBarSettingsView()
            } label: {
                Label(String(localized: "settings.tabBar.title"), systemImage: "square.grid.3x3")
            }

            // Sidebar settings only on iPad (not iPhone)
            if UIDevice.current.userInterfaceIdiom == .pad {
                NavigationLink {
                    SidebarSettingsView()
                } label: {
                    Label(String(localized: "settings.sidebar.title"), systemImage: "sidebar.leading")
                }
            }
            #endif

            #if os(macOS) || os(tvOS)
            NavigationLink {
                SidebarSettingsView()
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
        Section {
            Picker(
                String(localized: "settings.behavior.linkAction"),
                selection: $settings.defaultLinkAction
            ) {
                ForEach(DefaultLinkAction.allCases, id: \.self) { action in
                    Text(action.displayName).tag(action)
                }
            }
        } header: {
            Text(String(localized: "settings.behavior.linkAction.header"))
        } footer: {
            Text(String(localized: "settings.behavior.linkAction.footer"))
        }
    }
}

// MARK: - Clipboard Section

private struct ClipboardSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        Section {
            Toggle(
                String(localized: "settings.behavior.clipboardMonitoring"),
                isOn: $settings.clipboardURLDetectionEnabled
            )
        } header: {
            Text(String(localized: "settings.dataPrivacy.clipboard.header"))
        } footer: {
            Text(String(localized: "settings.behavior.clipboardMonitoring.footer"))
        }
    }
}

// MARK: - Video Actions Section

#if !os(tvOS)
private struct VideoActionsSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        Section {
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

            NavigationLink {
                SwipeActionsSettingsView()
            } label: {
                Label(String(localized: "settings.appearance.swipeActions"), systemImage: "hand.draw")
            }
        } header: {
            Text(String(localized: "settings.videoActions.header"))
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
        Section {
            Picker(
                String(localized: "settings.behavior.miniPlayer.minimizeBehavior"),
                selection: $settings.miniPlayerMinimizeBehavior
            ) {
                ForEach(MiniPlayerMinimizeBehavior.allCases, id: \.self) { behavior in
                    Text(behavior.displayName).tag(behavior)
                }
            }
        } header: {
            Text(String(localized: "settings.behavior.miniPlayer.header"))
        } footer: {
            Text(String(localized: "settings.behavior.miniPlayer.minimizeBehavior.footer"))
        }
    }
}
#endif

// MARK: - Handoff Section

private struct HandoffSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        Section {
            Toggle(
                String(localized: "settings.behavior.handoff"),
                isOn: $settings.handoffEnabled
            )
        } header: {
            Text(String(localized: "settings.behavior.handoff.header"))
        } footer: {
            Text(String(localized: "settings.behavior.handoff.footer"))
        }
    }
}

#Preview {
    NavigationStack {
        LayoutNavigationSettingsView()
    }
    .appEnvironment(.preview)
}
