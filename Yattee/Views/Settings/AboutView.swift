//
//  AboutView.swift
//  Yattee
//
//  About section containing app information and acknowledgements.
//

import SwiftUI

struct AboutView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsFormContainer {
            #if !os(tvOS)
            SettingsFormSection("settings.about.community") {
                communityLink("GitHub", icon: "github", url: "https://github.com/yattee/yattee")
                communityLink("Discord", icon: "discord", url: "https://yattee.stream/discord")
            }
            #endif

            SettingsFormSection {
                #if os(tvOS)
                NavigationLink {
                    TVSidebarDetailContainer(
                        systemImage: "person.3",
                        title: String(localized: "settings.contributors.title")
                    ) {
                        ContributorsView()
                    }
                } label: {
                    Label(String(localized: "settings.contributors.title"), systemImage: "person.3")
                }

                NavigationLink {
                    TVSidebarDetailContainer(
                        systemImage: "globe",
                        title: String(localized: "settings.translators.title")
                    ) {
                        TranslationContributorsView()
                    }
                } label: {
                    Label(String(localized: "settings.translators.title"), systemImage: "globe")
                }

                NavigationLink {
                    TVSidebarDetailContainer(
                        systemImage: "heart.text.square",
                        title: String(localized: "settings.acknowledgements.title")
                    ) {
                        AcknowledgementsView()
                    }
                } label: {
                    Label(String(localized: "settings.acknowledgements.title"), systemImage: "heart.text.square")
                }
                #else
                SettingsNavigationRow("settings.contributors.title", systemImage: "person.3") {
                    ContributorsView()
                }
                SettingsNavigationRow("settings.translators.title", systemImage: "globe") {
                    TranslationContributorsView()
                }
                SettingsNavigationRow("settings.acknowledgements.title", systemImage: "heart.text.square") {
                    AcknowledgementsView()
                }
                #endif
            }
            #if os(macOS)
            .labelStyle(FixedIconWidthLabelStyle())
            #endif

            SettingsFormSection {
                #if os(tvOS)
                NavigationLink {
                    TVSidebarDetailContainer(
                        systemImage: "cpu",
                        title: String(localized: "settings.advanced.deviceCapabilities"),
                        showsDismissButton: true
                    ) {
                        DeviceCapabilitiesView()
                    }
                } label: {
                    Label(String(localized: "settings.advanced.deviceCapabilities"), systemImage: "cpu")
                }
                #else
                SettingsNavigationRow("settings.advanced.deviceCapabilities", systemImage: "cpu") {
                    DeviceCapabilitiesView()
                }
                #endif
            }

            versionInfoSection
            mpvInfoSection
        }
        #if !os(tvOS)
        .navigationTitle(String(localized: "settings.about.title"))
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Sections

    @ViewBuilder
    private var versionInfoSection: some View {
        SettingsFormSection("settings.about.versionInfo") {
            versionInfoRow(label: String(localized: "settings.advanced.debug.appVersion"), value: appVersion)
            versionInfoRow(label: String(localized: "settings.advanced.debug.buildNumber"), value: buildNumber)
            versionInfoRow(label: String(localized: "settings.advanced.debug.osVersion"), value: osVersion)
        }
    }

    @ViewBuilder
    private func versionInfoRow(label: String, value: String) -> some View {
        #if os(macOS)
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        #else
        LabeledContent(label) {
            Text(value)
        }
        #endif
    }

    @ViewBuilder
    private var mpvInfoSection: some View {
        SettingsFormSection("settings.about.mpvInfo") {
            if let versionInfo = appEnvironment?.playerService.mpvVersionInfo {
                LabeledContent(String(localized: "settings.advanced.debug.mpvVersion")) {
                    Text(versionInfo.mpvVersion ?? "Unknown")
                        .foregroundStyle(.secondary)
                }

                LabeledContent(String(localized: "settings.advanced.debug.ffmpegVersion")) {
                    Text(versionInfo.ffmpegVersion ?? "Unknown")
                        .foregroundStyle(.secondary)
                }

                LabeledContent(String(localized: "settings.advanced.debug.libmpvAPI")) {
                    let major = (versionInfo.apiVersion >> 16) & 0xFFFF
                    let minor = versionInfo.apiVersion & 0xFFFF
                    Text("\(major).\(minor)")
                        .foregroundStyle(.secondary)
                }

                if let configuration = versionInfo.configuration, !configuration.isEmpty {
                    #if os(tvOS)
                    LabeledContent(String(localized: "settings.advanced.debug.mpvConfiguration")) {
                        Text(configuration)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    #else
                    DisclosureGroup(String(localized: "settings.advanced.debug.mpvConfiguration")) {
                        Text(configuration)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    #endif
                }
            } else {
                Text(String(localized: "settings.about.mpvInfoHint"))
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
    }

    // MARK: - Helpers

    private func communityLink(_ name: String, icon: String, url: String) -> some View {
        Button {
            if let url = URL(string: url) {
                openURL(url)
            }
        } label: {
            HStack {
                Label {
                    Text(name)
                } icon: {
                    Image(icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Computed Properties

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

    private var osVersion: String {
        #if os(iOS)
        return "iOS \(UIDevice.current.systemVersion)"
        #elseif os(macOS)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #elseif os(tvOS)
        return "tvOS \(UIDevice.current.systemVersion)"
        #else
        return "Unknown"
        #endif
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
