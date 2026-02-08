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
        Form {
            Section {
                communityLink("GitHub", icon: "github", url: "https://github.com/yattee/yattee")
                communityLink("Discord", icon: "discord", url: "https://yattee.stream/discord")
            } header: {
                Text("Community")
            }

            Section {
                NavigationLink {
                    ContributorsView()
                } label: {
                    Label(String(localized: "settings.contributors.title"), systemImage: "person.3")
                }

                NavigationLink {
                    TranslationContributorsView()
                } label: {
                    Label(String(localized: "settings.translators.title"), systemImage: "globe")
                }

                NavigationLink {
                    AcknowledgementsView()
                } label: {
                    Label(String(localized: "settings.acknowledgements.title"), systemImage: "heart.text.square")
                }
            }

            Section {
                NavigationLink {
                    DeviceCapabilitiesView()
                } label: {
                    Label(String(localized: "settings.advanced.deviceCapabilities"), systemImage: "cpu")
                }
            }

            versionInfoSection
            mpvInfoSection
        }
        .navigationTitle(String(localized: "settings.about.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Sections

    @ViewBuilder
    private var versionInfoSection: some View {
        Section {
            LabeledContent(String(localized: "settings.advanced.debug.appVersion")) {
                Text(appVersion)
            }

            LabeledContent(String(localized: "settings.advanced.debug.buildNumber")) {
                Text(buildNumber)
            }

            LabeledContent(String(localized: "settings.advanced.debug.osVersion")) {
                Text(osVersion)
            }
        } header: {
            Text(String(localized: "settings.about.versionInfo"))
        }
    }

    @ViewBuilder
    private var mpvInfoSection: some View {
        Section {
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
        } header: {
            Text(String(localized: "settings.about.mpvInfo"))
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
