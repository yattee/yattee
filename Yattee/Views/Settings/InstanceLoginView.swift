//
//  InstanceLoginView.swift
//  Yattee
//
//  Shared login sheet for Invidious and Piped accounts.
//

import SwiftUI

struct InstanceLoginView: View {
    let instance: Instance
    /// Receives the credential **and** the identifier the user signed in with,
    /// and reports whether it was stored.
    ///
    /// The identifier is handed back rather than stored here because it belongs
    /// beside the credential in the Keychain, not in synced account metadata —
    /// so only the caller, which knows which account this login is for, can
    /// file it correctly.
    ///
    /// The return value matters because signing in successfully is not the same
    /// as having somewhere to keep the result: dismissing on a Keychain failure
    /// would throw away what the user typed and make them do it all again.
    let onLoginSuccess: (_ credential: String, _ username: String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        #if os(tvOS)
        TVSidebarDetailContainer(systemImage: "person.badge.key", title: String(localized: "login.title")) {
            formContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .accessibilityIdentifier("instance.login.view")
        #else
        NavigationStack {
            formContent
                .navigationTitle(String(localized: "login.title"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "common.cancel")) {
                            dismiss()
                        }
                    }
                }
                .accessibilityIdentifier("instance.login.view")
        }
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 350)
        #endif
        #endif
    }

    private var formContent: some View {
        Form {
            Section {
                #if os(tvOS)
                TVSettingsTextField(title: usernameFieldLabel, text: $username)
                TVSettingsTextField(title: String(localized: "login.password"), text: $password, isSecure: true)
                #else
                TextField(usernameFieldLabel, text: $username)
                    .textContentType(.username)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("instance.login.usernameField")

                SecureField(String(localized: "login.password"), text: $password)
                    .textContentType(.password)
                    .accessibilityIdentifier("instance.login.passwordField")
                #endif
            } header: {
                Text(String(localized: "login.header.credentials"))
            } footer: {
                Text(footerText)
            }

            if let error = errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("instance.login.error")
                }
            }

            Section {
                Button {
                    login()
                } label: {
                    if isLoading {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text(String(localized: "login.loggingIn"))
                        }
                    } else {
                        Text(String(localized: "login.signIn"))
                    }
                }
                .disabled(username.isEmpty || password.isEmpty || isLoading)
                .accessibilityIdentifier("instance.login.submitButton")
                #if os(tvOS)
                .buttonStyle(TVSettingsButtonStyle())
                #endif
            }
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }

    // MARK: - Computed Properties

    /// Returns the appropriate label for the username field based on instance type.
    private var usernameFieldLabel: String {
        switch instance.type {
        case .piped:
            return String(localized: "login.username")
        case .invidious:
            return String(localized: "login.email")
        default:
            return String(localized: "login.username")
        }
    }

    /// Returns the appropriate footer text based on instance type.
    private var footerText: String {
        switch instance.type {
        case .piped:
            return String(localized: "login.footer.pipedAccount \(instance.displayName)")
        case .invidious:
            return String(localized: "login.footer.invidiousAccount \(instance.displayName)")
        default:
            return ""
        }
    }

    // MARK: - Actions

    private func login() {
        guard let appEnvironment else { return }

        isLoading = true
        errorMessage = nil

        // Which Apple identity this login is being made under. Credentials are
        // filed per identity, and the round trip below leaves room for the
        // scope to move — storing afterwards would file the account obtained
        // here in somebody else's namespace, and sync it to their Keychain.
        let scopeAtStart = appEnvironment.credentialIdentityScope.current

        Task {
            do {
                let credential = try await performLogin(appEnvironment: appEnvironment)

                await MainActor.run {
                    // Only a move between two *named* identities is a mismatch.
                    // Unresolved at either end is left to `storeLogin`, which
                    // already refuses to write under a scope it cannot name —
                    // rejecting here as well would turn an ordinary sign-in
                    // that began before iCloud settled, or a tokenless scope
                    // revalidating on activation, into a failed login.
                    if let scopeAtStart,
                       let scopeNow = appEnvironment.credentialIdentityScope.current,
                       scopeNow != scopeAtStart {
                        errorMessage = String(localized: "accounts.signIn.identityChanged")
                        isLoading = false
                        return
                    }

                    guard onLoginSuccess(credential, username) else {
                        // The failure is reported by a toast from the storing
                        // side; staying open keeps the form filled in so the
                        // user can retry once it can succeed.
                        isLoading = false
                        return
                    }
                    dismiss()
                }
            } catch APIError.unauthorized {
                await MainActor.run {
                    errorMessage = String(localized: "login.error.invalidCredentials")
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    /// Performs the login based on instance type.
    /// - Returns: The credential (SID for Invidious, token for Piped)
    private func performLogin(appEnvironment: AppEnvironment) async throws -> String {
        // If the instance sits behind an HTTP Basic Auth reverse proxy, the login
        // POST must carry that proxy's Authorization header too — otherwise the
        // request 401s before reaching the upstream login endpoint. Bake the
        // header into a fresh per-instance HTTPClient.
        let basicAuthHeader = appEnvironment.basicAuthCredentialsManager.basicAuthHeader(for: instance)
        let extraHeaders: [String: String]? = basicAuthHeader.map { ["Authorization": $0] }

        let httpClient: HTTPClient
        if let basicAuthHeader {
            httpClient = appEnvironment.httpClientFactory.createClient(for: instance)
            await httpClient.setDefaultHeaders(["Authorization": basicAuthHeader])
        } else {
            httpClient = appEnvironment.httpClient
        }

        switch instance.type {
        case .invidious:
            // InvidiousAPI.login uses its own URLSession (to handle redirect/Set-Cookie),
            // so it doesn't inherit defaultHeaders from the injected HTTPClient. Pass
            // the basic-auth header explicitly so the login POST passes the proxy.
            let api = InvidiousAPI(httpClient: httpClient)
            return try await api.login(email: username, password: password, instance: instance, extraHeaders: extraHeaders)

        case .piped:
            // PipedAPI.login uses httpClient.fetch which DOES inherit defaultHeaders,
            // so the basic-auth header on the per-instance client is sufficient.
            let api = PipedAPI(httpClient: httpClient)
            return try await api.login(username: username, password: password, instance: instance)

        default:
            throw APIError.notSupported
        }
    }
}

// MARK: - Preview

#Preview("Invidious") {
    InstanceLoginView(
        instance: Instance(type: .invidious, url: URL(string: "https://invidious.example.com")!)
    ) { _, _ in true }
    .appEnvironment(.preview)
}

#Preview("Piped") {
    InstanceLoginView(
        instance: Instance(type: .piped, url: URL(string: "https://piped.example.com")!)
    ) { _, _ in true }
    .appEnvironment(.preview)
}
