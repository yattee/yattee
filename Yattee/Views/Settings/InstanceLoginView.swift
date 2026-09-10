//
//  InstanceLoginView.swift
//  Yattee
//
//  Shared login sheet for Invidious and Piped accounts.
//

import SwiftUI

struct InstanceLoginView: View {
    let instance: Instance

    /// Whether signing in is optional here.
    ///
    /// Set when the sheet follows an action that already succeeded — adding a
    /// source, which is saved before this appears. The way out is then "Skip"
    /// rather than "Cancel", and it is offered as a button in the form as well:
    /// tvOS has no cancellation affordance at all, so an optional step without
    /// one would be a dead end there.
    var isOptionalStep: Bool = false

    /// The identifier to start the form with, when there is one to start from.
    ///
    /// Signing in again is almost always the same person proving themselves
    /// once more, and the identifier they used is already on the device — beside
    /// the credential, in the Keychain. Retyping it is work the app can do.
    /// A new login has nobody to name and passes nothing.
    var initialUsername: String?

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
                        Button(String(localized: isOptionalStep ? "common.skip" : "common.cancel")) {
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

            if isOptionalStep {
                Section {
                    Button {
                        dismiss()
                    } label: {
                        Text(String(localized: "common.skip"))
                    }
                    .accessibilityIdentifier("instance.login.skipButton")
                    #if os(tvOS)
                    .buttonStyle(TVSettingsButtonStyle())
                    #endif
                } footer: {
                    Text(String(localized: "login.footer.optionalStep"))
                }
            }
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .onAppear {
            // Only ever fills an untouched field: the sheet's body runs again
            // for every keystroke, and a prefill that reasserted itself would
            // fight the user editing it.
            if let initialUsername, !initialUsername.isEmpty, username.isEmpty {
                username = initialUsername
            }
        }
    }

    // MARK: - Computed Properties

    /// What the first field is called on this backend.
    ///
    /// Named per backend rather than genericised: every backend that has
    /// accounts signs in by username — Invidious posts one in a form field it
    /// still calls `email`, but an email is never what it wants. Every case is
    /// spelled out so a backend that gains accounts —
    /// `AccountCapabilities.supportsAccounts` is what decides that — arrives
    /// here rather than falling through to somebody else's wording.
    private var usernameFieldLabel: String {
        switch instance.type {
        case .piped:
            return String(localized: "login.username")
        case .invidious:
            return String(localized: "login.username")
        case .yatteeServer:
            return String(localized: "login.username")
        case .peertube:
            return String(localized: "login.username")
        }
    }

    /// What this form is signing in to, said in the user's terms.
    private var footerText: String {
        switch instance.type {
        case .piped:
            return String(localized: "login.footer.pipedAccount \(instance.displayName)")
        case .invidious:
            return String(localized: "login.footer.invidiousAccount \(instance.displayName)")
        case .yatteeServer:
            return String(localized: "login.footer.yatteeServerAccount \(instance.displayName)")
        case .peertube:
            // No account concept at all, so no sign-in is offered — and if one
            // ever were, an empty footer explains nothing.
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
        // The service owns the per-instance configuration a login needs — the
        // reverse-proxy basic auth (without which the POST 401s before reaching
        // the upstream login endpoint), the certificate policy, and the
        // User-Agent instances may insist on.
        try await appEnvironment.contentService.login(
            username: username,
            password: password,
            instance: instance
        )
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
