//
//  AddWebDAVView.swift
//  Yattee
//
//  View for adding a WebDAV share as a media source.
//

import SwiftUI

struct AddWebDAVView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    // MARK: - State

    @State private var name = ""
    @State private var urlString = ""
    @State private var username = ""
    @State private var password = ""
    @State private var allowInvalidCertificates = false

    @State private var isTesting = false
    @State private var testResult: SourceTestResult?
    @State private var testProgress: String?

    // Pre-filled from network discovery
    var prefillURL: URL?
    var prefillName: String?
    var prefillAllowInvalidCertificates: Bool = false

    // Closure to dismiss the parent sheet
    var dismissSheet: DismissAction?

    // MARK: - Computed Properties

    private var canAdd: Bool {
        !name.isEmpty && !urlString.isEmpty && URL(string: urlString) != nil
    }

    // MARK: - Body

    var body: some View {
        Form {
            nameSection
            serverSection
            authSection
            securitySection

            if let result = testResult {
                SourceTestResultSection(result: result)
            }

            actionSection
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .navigationTitle(String(localized: "sources.addWebDAV"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            if let url = prefillURL {
                urlString = url.absoluteString
            }
            if let prefillName, name.isEmpty {
                name = prefillName
            }
            if prefillAllowInvalidCertificates {
                allowInvalidCertificates = true
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
            TVSettingsTextField(title: String(localized: "sources.placeholder.webdavUrl"), text: $urlString)
            #else
            TextField(String(localized: "sources.placeholder.webdavUrl"), text: $urlString)
                .textContentType(.URL)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            #endif
        } footer: {
            Text(String(localized: "sources.footer.webdav"))
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

    private var securitySection: some View {
        Section {
            #if os(tvOS)
            TVSettingsToggle(
                title: String(localized: "sources.field.allowInvalidCertificates"),
                isOn: $allowInvalidCertificates
            )
            #else
            Toggle(String(localized: "sources.field.allowInvalidCertificates"), isOn: $allowInvalidCertificates)
            #endif
        } header: {
            Text(String(localized: "sources.header.security"))
        } footer: {
            Text(String(localized: "sources.footer.allowInvalidCertificates"))
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
        guard let appEnvironment,
              let url = URL(string: urlString) else { return }

        isTesting = true
        testResult = nil
        testProgress = String(localized: "sources.testing.connecting")

        let source = MediaSource.webdav(
            name: name,
            url: url,
            username: username.isEmpty ? nil : username,
            allowInvalidCertificates: allowInvalidCertificates
        )

        let webDAVClient = appEnvironment.webDAVClientFactory.createClient(for: source)

        Task {
            do {
                _ = try await webDAVClient.testConnection(
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
        AddWebDAVView()
            .appEnvironment(.preview)
    }
}
