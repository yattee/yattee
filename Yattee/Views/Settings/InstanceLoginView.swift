//
//  InstanceLoginView.swift
//  Yattee
//
//  Shared login sheet for Invidious and Piped accounts.
//

import SwiftUI

struct InstanceLoginView: View {
    let instance: Instance
    let onLoginSuccess: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

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
                    Text(String(localized: "login.title"))
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    Color.clear.frame(width: 100)
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 24)

                formContent
            }
            .accessibilityIdentifier("instance.login.view")
            #else
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
            #endif
        }
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

        Task {
            do {
                let credential = try await performLogin(appEnvironment: appEnvironment)

                await MainActor.run {
                    onLoginSuccess(credential)
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
        switch instance.type {
        case .invidious:
            let api = InvidiousAPI(httpClient: appEnvironment.httpClient)
            return try await api.login(email: username, password: password, instance: instance)

        case .piped:
            let api = PipedAPI(httpClient: appEnvironment.httpClient)
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
    ) { _ in }
    .appEnvironment(.preview)
}

#Preview("Piped") {
    InstanceLoginView(
        instance: Instance(type: .piped, url: URL(string: "https://piped.example.com")!)
    ) { _ in }
    .appEnvironment(.preview)
}
