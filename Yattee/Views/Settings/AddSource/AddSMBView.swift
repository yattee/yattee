//
//  AddSMBView.swift
//  Yattee
//
//  View for adding an SMB (Samba) share as a media source.
//

import SwiftUI

struct AddSMBView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    // MARK: - State

    @State private var name = ""
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var protocolVersion: SMBProtocol = .auto

    @State private var isTesting = false
    @State private var testResult: SourceTestResult?
    @State private var testProgress: String?

    // Pre-filled from network discovery
    var prefillServer: String?
    var prefillName: String?

    // Closure to dismiss the parent sheet
    var dismissSheet: DismissAction?

    // MARK: - Computed Properties

    private var canAdd: Bool {
        !name.isEmpty && !server.isEmpty
    }

    // MARK: - Body

    var body: some View {
        Form {
            nameSection
            serverSection
            authSection
            protocolSection

            if let result = testResult {
                SourceTestResultSection(result: result)
            }

            actionSection
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .navigationTitle(String(localized: "sources.addSMB"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            if let prefillServer {
                server = prefillServer
            }
            if let prefillName, name.isEmpty {
                name = prefillName
            }
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section {
            #if os(tvOS)
            TVSettingsTextField(title: String(localized: "sources.field.name"), text: $name)
            #else
            TextField(String(localized: "sources.field.name"), text: $name)
            #endif
        } footer: {
            Text(String(localized: "sources.footer.displayName"))
        }
    }

    private var serverSection: some View {
        Section {
            #if os(tvOS)
            TVSettingsTextField(title: String(localized: "sources.placeholder.smbServer"), text: $server)
            #else
            TextField(String(localized: "sources.placeholder.smbServer"), text: $server, prompt: Text(String(localized: "sources.placeholder.smbServer")))
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            #endif
        } footer: {
            Text(String(localized: "sources.footer.smb"))
        }
    }

    private var authSection: some View {
        Section {
            #if os(tvOS)
            TVSettingsTextField(title: String(localized: "sources.field.usernameOptional"), text: $username)
            TVSettingsTextField(title: String(localized: "sources.field.passwordOptional"), text: $password, isSecure: true)
            #else
            TextField(String(localized: "sources.field.usernameOptional"), text: $username)
                .textContentType(.username)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()

            SecureField(String(localized: "sources.field.passwordOptional"), text: $password)
                .textContentType(.password)
            #endif
        } header: {
            Text(String(localized: "sources.header.auth"))
        } footer: {
            Text(String(localized: "sources.footer.auth"))
        }
    }

    private var protocolSection: some View {
        Section {
            Picker(String(localized: "sources.field.smbProtocol"), selection: $protocolVersion) {
                ForEach(SMBProtocol.allCases, id: \.self) { proto in
                    Text(proto.displayName).tag(proto)
                }
            }
        } header: {
            Text(String(localized: "sources.header.advanced"))
        } footer: {
            Text(String(localized: "sources.footer.smbProtocol"))
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                addSource()
            } label: {
                if isTesting {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text(testProgress ?? String(localized: "sources.testing"))
                    }
                } else {
                    Text(String(localized: "sources.addSource"))
                }
            }
            .disabled(!canAdd || isTesting)
            #if os(tvOS)
            .buttonStyle(TVSettingsButtonStyle())
            #endif
        }
    }

    // MARK: - Actions

    private func addSource() {
        guard let appEnvironment else { return }

        let urlString = "smb://\(server)"
        guard let encodedURLString = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encodedURLString) else {
            testResult = .failure(String(localized: "sources.error.invalidSMBAddress"))
            return
        }

        isTesting = true
        testResult = nil
        testProgress = String(localized: "sources.testing.connecting")

        let source = MediaSource.smb(
            name: name,
            url: url,
            username: username.isEmpty ? nil : username,
            protocolVersion: protocolVersion
        )

        Task {
            do {
                _ = try await appEnvironment.smbClient.testConnection(
                    source: source,
                    password: password.isEmpty ? nil : password
                )

                await MainActor.run {
                    if !password.isEmpty {
                        appEnvironment.mediaSourcesManager.setPassword(password, for: source)
                    }

                    appEnvironment.mediaSourcesManager.add(source)
                    isTesting = false
                    testProgress = nil
                    if let dismissSheet {
                        dismissSheet()
                    } else {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    testProgress = nil
                    testResult = .failure(error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AddSMBView()
            .appEnvironment(.preview)
    }
}
