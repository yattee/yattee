//
//  AddSourceView.swift
//  Yattee
//
//  Selection screen for adding new sources. Presents a list of source types
//  with NavigationLinks to dedicated forms for each type.
//

import SwiftUI

struct AddSourceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    // Network discovery sheet
    @State private var showingNetworkDiscovery = false
    @State private var selectedShareType: DiscoveredShare.ShareType?

    // Navigation destinations from network discovery
    @State private var navigateToWebDAV = false
    @State private var navigateToSMB = false
    @State private var discoveredWebDAVURL: URL?
    @State private var discoveredSMBServer: String?
    @State private var discoveredName: String?
    @State private var discoveredAllowInvalidCerts = false

    var body: some View {
        NavigationStack {
            #if os(tvOS)
            VStack(spacing: 0) {
                HStack {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                    .buttonStyle(TVToolbarButtonStyle())
                    Spacer()
                    Text(String(localized: "sources.newSource"))
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(String(localized: "common.cancel"))
                        .opacity(0)
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 24)

                listContent
            }
            .navigationDestination(isPresented: $navigateToWebDAV) {
                AddWebDAVView(
                    prefillURL: discoveredWebDAVURL,
                    prefillName: discoveredName,
                    prefillAllowInvalidCertificates: discoveredAllowInvalidCerts,
                    dismissSheet: dismiss
                )
            }
            .navigationDestination(isPresented: $navigateToSMB) {
                AddSMBView(
                    prefillServer: discoveredSMBServer,
                    prefillName: discoveredName,
                    dismissSheet: dismiss
                )
            }
            #else
            listContent
                .navigationTitle(String(localized: "sources.newSource"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .cancel) {
                            dismiss()
                        } label: {
                            Label("Close", systemImage: "xmark")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
                .navigationDestination(isPresented: $navigateToWebDAV) {
                    AddWebDAVView(
                        prefillURL: discoveredWebDAVURL,
                        prefillName: discoveredName,
                        prefillAllowInvalidCertificates: discoveredAllowInvalidCerts,
                        dismissSheet: dismiss
                    )
                }
                .navigationDestination(isPresented: $navigateToSMB) {
                    AddSMBView(
                        prefillServer: discoveredSMBServer,
                        prefillName: discoveredName,
                        dismissSheet: dismiss
                    )
                }
            #endif
        }
        .sheet(isPresented: $showingNetworkDiscovery) {
            NetworkShareDiscoverySheet(filterType: selectedShareType) { share in
                handleSelectedShare(share)
            }
        }
    }

    private var listContent: some View {
        List {
            Section {
                #if !os(tvOS)
                NavigationLink {
                    AddLocalFolderView(dismissSheet: dismiss)
                } label: {
                    Label(String(localized: "sources.addLocalFolder"), systemImage: "folder")
                }
                #endif

                NavigationLink {
                    AddWebDAVView(dismissSheet: dismiss)
                } label: {
                    Label(String(localized: "sources.addWebDAV"), systemImage: "externaldrive.connected.to.line.below")
                }

                NavigationLink {
                    AddSMBView(dismissSheet: dismiss)
                } label: {
                    Label(String(localized: "sources.addSMB"), systemImage: "server.rack")
                }

                NavigationLink {
                    AddRemoteServerView(dismissSheet: dismiss)
                } label: {
                    Label(String(localized: "sources.addRemoteServer"), systemImage: "globe")
                }

                NavigationLink {
                    if let appEnvironment {
                        PeerTubeInstancesExploreView()
                            .appEnvironment(appEnvironment)
                    }
                } label: {
                    Label {
                        Text(String(localized: "sources.browsePeerTube"))
                    } icon: {
                        Image("peertube")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                    }
                }
            }

            Section {
                Button {
                    selectedShareType = nil
                    showingNetworkDiscovery = true
                } label: {
                    Label(String(localized: "discovery.scanNetwork"), systemImage: "wifi")
                }
                #if os(tvOS)
                .buttonStyle(TVSettingsButtonStyle())
                #endif
            } footer: {
                Text(String(localized: "sources.footer.discovery"))
            }
        }
    }

    private func handleSelectedShare(_ share: DiscoveredShare) {
        discoveredName = share.name

        switch share.type {
        case .webdav, .webdavs:
            discoveredWebDAVURL = share.url
            discoveredAllowInvalidCerts = share.type == .webdavs
            navigateToWebDAV = true

        case .smb:
            discoveredSMBServer = share.host
            navigateToSMB = true
        }
    }
}

// MARK: - Preview

#Preview {
    AddSourceView()
        .appEnvironment(.preview)
}
