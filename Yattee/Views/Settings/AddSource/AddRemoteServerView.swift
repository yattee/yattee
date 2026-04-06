//
//  AddRemoteServerView.swift
//  Yattee
//
//  View for adding a remote server (Invidious, Piped, PeerTube, Yattee Server) as a source.
//

import SwiftUI

// MARK: - UI State Machine

/// Represents the current state of the Add Remote Server view.
private enum RemoteServerUIState: Equatable {
    /// Initial state: URL field visible, manual fields hidden
    case initial
    /// Detection in progress: skeleton loading visible
    case detecting
    /// Detection succeeded: fields revealed with pre-filled values
    case detected(InstanceType)
    /// Detection failed: fields auto-revealed with error message
    case error(String)

    static func == (lhs: RemoteServerUIState, rhs: RemoteServerUIState) -> Bool {
        switch (lhs, rhs) {
        case (.initial, .initial): return true
        case (.detecting, .detecting): return true
        case (.detected(let a), .detected(let b)): return a == b
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

struct AddRemoteServerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    // MARK: - UI State

    @State private var uiState: RemoteServerUIState = .initial
    @State private var detectionTask: Task<Void, Never>?

    // MARK: - URL Entry

    @State private var urlString = ""

    // MARK: - Server Configuration

    @State private var name = ""
    @State private var detectedType: InstanceType?
    @State private var detectionResult: InstanceDetectionResult?
    @State private var allowInvalidCertificates = false
    @State private var showSSLToggle = false

    // Yattee Server authentication (always required)
    @State private var yatteeServerUsername = ""
    @State private var yatteeServerPassword = ""
    @State private var isValidatingCredentials = false
    @State private var credentialValidationError: String?

    // Yattee Server warning dialog
    @State private var showingYatteeServerWarning = false
    @State private var pendingYatteeServerInstance: Instance?

    // Closure to dismiss the parent sheet
    var dismissSheet: DismissAction?

    // MARK: - Computed Properties

    private var isFieldsRevealed: Bool {
        switch uiState {
        case .initial, .detecting:
            return false
        case .detected, .error:
            return true
        }
    }

    private var canAdd: Bool {
        guard !urlString.isEmpty else { return false }

        // For detected Yattee Server, require credentials
        if detectedType == .yatteeServer {
            return !yatteeServerUsername.isEmpty && !yatteeServerPassword.isEmpty
        }

        return true
    }

    // MARK: - Body

    var body: some View {
        #if os(tvOS)
        VStack(spacing: 0) {
            formContent
        }
        .confirmationDialog(
            String(localized: "sources.yatteeServer.warning.title"),
            isPresented: $showingYatteeServerWarning,
            titleVisibility: .visible
        ) {
            yatteeServerWarningButtons
        } message: {
            Text(String(localized: "sources.yatteeServer.warning.message"))
        }
        .presentationCompactAdaptation(.sheet)
        #else
        formContent
            .navigationTitle(String(localized: "sources.addRemoteServer"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .confirmationDialog(
                String(localized: "sources.yatteeServer.warning.title"),
                isPresented: $showingYatteeServerWarning,
                titleVisibility: .visible
            ) {
                yatteeServerWarningButtons
            } message: {
                Text(String(localized: "sources.yatteeServer.warning.message"))
            }
            .presentationCompactAdaptation(.sheet)
        #endif
    }

    @ViewBuilder
    private var yatteeServerWarningButtons: some View {
        Button(String(localized: "sources.yatteeServer.warning.disableOthers"), role: .destructive) {
            if let instance = pendingYatteeServerInstance {
                appEnvironment?.instancesManager.disableOtherYatteeServerInstances(except: instance.id)
                appEnvironment?.instancesManager.add(instance)
                if let dismissSheet {
                    dismissSheet()
                } else {
                    dismiss()
                }
            }
        }
        Button(String(localized: "common.cancel"), role: .cancel) {
            pendingYatteeServerInstance = nil
        }
    }

    // MARK: - Form Content

    private var formContent: some View {
        Form {
            urlEntrySection

            if case .detecting = uiState {
                skeletonSection
            }

            if case .error(let message) = uiState {
                errorSection(message)
            }

            if isFieldsRevealed {
                serverConfigurationFields
                actionSection
            }
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }

    // MARK: - URL Entry Section

    private var urlEntrySection: some View {
        Section {
            #if os(tvOS)
            TVSettingsTextField(title: String(localized: "sources.placeholder.urlOrAddress"), text: $urlString)
                .onChange(of: urlString) { _, _ in
                    handleURLChange()
                }

            if !isFieldsRevealed {
                Button {
                    startDetection()
                } label: {
                    if case .detecting = uiState {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text(String(localized: "sources.detecting"))
                        }
                    } else {
                        Text(String(localized: "sources.detect"))
                    }
                }
                .buttonStyle(TVSettingsButtonStyle())
                .disabled(urlString.isEmpty || uiState == .detecting)
            }
            #else
            TextField(String(localized: "sources.placeholder.urlOrAddress"), text: $urlString)
                .textContentType(.URL)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .accessibilityIdentifier("addRemoteServer.urlField")
                .onChange(of: urlString) { _, _ in
                    handleURLChange()
                }

            if !isFieldsRevealed {
                Button {
                    startDetection()
                } label: {
                    HStack(spacing: 6) {
                        if case .detecting = uiState {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(String(localized: "sources.detect"))
                    }
                }
                .disabled(urlString.isEmpty || uiState == .detecting)
                .accessibilityIdentifier("addRemoteServer.detectButton")
            }
            #endif
        } footer: {
            Text(String(localized: "sources.footer.remoteServer"))
        }
    }

    // MARK: - Skeleton Loading Section

    private var skeletonSection: some View {
        Group {
            Section {
                Text("my-server.example.com")
                    .redacted(reason: .placeholder)
            } header: {
                Text(String(localized: "sources.detecting"))
            }

            Section {
                Text(String(localized: "sources.field.name"))
                    .redacted(reason: .placeholder)
            }
        }
    }

    // MARK: - Error Section

    private func errorSection(_ message: String) -> some View {
        Section {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityIdentifier("addRemoteServer.detectionError")
        }
    }

    // MARK: - Server Configuration Fields

    @ViewBuilder
    private var serverConfigurationFields: some View {
        Section {
            #if os(tvOS)
            TVSettingsTextField(title: String(localized: "sources.field.nameOptional"), text: $name)
            #else
            TextField(String(localized: "sources.field.nameOptional"), text: $name)
            #endif
        } header: {
            Text(String(localized: "sources.header.displayName"))
        }

        // Show detected type badge
        if let detectedType {
            Section {
                HStack {
                    Label(detectedType.displayName, systemImage: detectedType.systemImage)
                        .foregroundStyle(.green)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .accessibilityIdentifier("addRemoteServer.detectedType")
            } header: {
                Text(String(localized: "sources.detectedType"))
            }
        }

        // SSL Certificate toggle (show if SSL error occurred)
        if showSSLToggle {
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

        // Authentication fields for Yattee Server (always required)
        if detectedType == .yatteeServer {
            Section {
                #if os(tvOS)
                TVSettingsTextField(title: String(localized: "sources.field.username"), text: $yatteeServerUsername)
                TVSettingsTextField(title: String(localized: "sources.field.password"), text: $yatteeServerPassword, isSecure: true)
                #else
                TextField(String(localized: "sources.field.username"), text: $yatteeServerUsername)
                    .textContentType(.username)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()

                SecureField(String(localized: "sources.field.password"), text: $yatteeServerPassword)
                    .textContentType(.password)
                #endif
            } header: {
                Text(String(localized: "sources.header.auth"))
            } footer: {
                Text(String(localized: "sources.footer.yatteeServerAuth"))
            }

            if let error = credentialValidationError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Action Section

    private var actionSection: some View {
        Section {
            Button {
                addSource()
            } label: {
                if isValidatingCredentials {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "sources.validatingCredentials"))
                    }
                } else {
                    Text(String(localized: "sources.addSource"))
                }
            }
            .accessibilityIdentifier("addRemoteServer.actionButton")
            .disabled(!canAdd || isValidatingCredentials)
            #if os(tvOS)
            .buttonStyle(TVSettingsButtonStyle())
            #endif
        }
    }

    // MARK: - Actions

    private func handleURLChange() {
        cancelDetection()

        if isFieldsRevealed {
            withAnimation {
                uiState = .initial
                detectedType = nil
                detectionResult = nil
                showSSLToggle = false
            }
        }
    }

    private func cancelDetection() {
        detectionTask?.cancel()
        detectionTask = nil
    }

    private func startDetection() {
        guard !urlString.isEmpty else { return }

        guard let url = Instance.normalizeSourceURL(urlString) else {
            withAnimation {
                uiState = .error(String(localized: "sources.validation.invalidURL"))
            }
            return
        }

        cancelDetection()

        withAnimation {
            uiState = .detecting
        }

        detectionTask = Task {
            await performDetection(url: url)
        }
    }

    private func performDetection(url: URL) async {
        guard let appEnvironment else { return }

        let detector: InstanceDetector
        if allowInvalidCertificates {
            let insecureClient = appEnvironment.httpClientFactory.createClient(allowInvalidCertificates: true)
            detector = InstanceDetector(httpClient: insecureClient)
        } else {
            detector = appEnvironment.instanceDetector
        }

        let result = await detector.detectWithResult(url: url)

        if Task.isCancelled { return }

        await MainActor.run {
            switch result {
            case .success(let detectionResult):
                LoggingService.shared.debug("[AddRemoteServerView] Detection succeeded: \(detectionResult.type)", category: .api)
                withAnimation {
                    self.detectedType = detectionResult.type
                    self.detectionResult = detectionResult
                    self.uiState = .detected(detectionResult.type)
                }

            case .failure(let error):
                LoggingService.shared.debug("[AddRemoteServerView] Detection failed: \(error)", category: .api)
                withAnimation {
                    if case .sslCertificateError = error {
                        self.showSSLToggle = true
                    }
                    self.uiState = .error(error.localizedDescription)
                }
            }
        }
    }

    private func addSource() {
        guard let appEnvironment else { return }

        guard let url = Instance.normalizeSourceURL(urlString) else {
            withAnimation {
                uiState = .error(String(localized: "sources.validation.invalidURL"))
            }
            return
        }

        // If we have a detected type, use it directly
        if let detectedType {
            addServer(type: detectedType, url: url, appEnvironment: appEnvironment)
            return
        }

        // Otherwise, detect first then add
        withAnimation {
            uiState = .detecting
        }

        detectionTask = Task {
            let detector: InstanceDetector
            if allowInvalidCertificates {
                let insecureClient = appEnvironment.httpClientFactory.createClient(allowInvalidCertificates: true)
                detector = InstanceDetector(httpClient: insecureClient)
            } else {
                detector = appEnvironment.instanceDetector
            }

            let result = await detector.detectWithResult(url: url)

            if Task.isCancelled { return }

            await MainActor.run {
                switch result {
                case .success(let detectionResult):
                    self.detectedType = detectionResult.type
                    self.detectionResult = detectionResult

                    // For Yattee Server, show auth fields instead of auto-adding
                    if detectionResult.type == .yatteeServer {
                        withAnimation {
                            self.uiState = .detected(detectionResult.type)
                        }
                    } else {
                        // Auto-add for other types
                        addServer(type: detectionResult.type, url: url, appEnvironment: appEnvironment)
                    }

                case .failure(let error):
                    withAnimation {
                        if case .sslCertificateError = error {
                            self.showSSLToggle = true
                        }
                        self.uiState = .error(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func addServer(type: InstanceType, url: URL, appEnvironment: AppEnvironment) {
        // For Yattee Server, always validate credentials first
        if type == .yatteeServer {
            guard !yatteeServerUsername.isEmpty, !yatteeServerPassword.isEmpty else {
                credentialValidationError = String(localized: "sources.error.credentialsRequired")
                return
            }

            isValidatingCredentials = true
            credentialValidationError = nil

            Task {
                let isValid = await validateYatteeServerCredentials(
                    url: url,
                    username: yatteeServerUsername,
                    password: yatteeServerPassword,
                    appEnvironment: appEnvironment
                )

                await MainActor.run {
                    isValidatingCredentials = false

                    if isValid {
                        let instance = Instance(
                            type: type,
                            url: url,
                            name: name.isEmpty ? nil : name,
                            allowInvalidCertificates: allowInvalidCertificates
                        )

                        appEnvironment.basicAuthCredentialsManager.setCredentials(
                            username: yatteeServerUsername,
                            password: yatteeServerPassword,
                            for: instance
                        )

                        if !appEnvironment.instancesManager.enabledYatteeServerInstances.isEmpty {
                            pendingYatteeServerInstance = instance
                            showingYatteeServerWarning = true
                        } else {
                            appEnvironment.instancesManager.add(instance)
                            if let dismissSheet {
                                dismissSheet()
                            } else {
                                dismiss()
                            }
                        }
                    } else {
                        credentialValidationError = String(localized: "sources.error.invalidCredentials")
                    }
                }
            }
            return
        }

        // For other instance types (no auth required)
        let instance = Instance(
            type: type,
            url: url,
            name: name.isEmpty ? nil : name,
            allowInvalidCertificates: allowInvalidCertificates
        )

        appEnvironment.instancesManager.add(instance)
        if let dismissSheet {
            dismissSheet()
        } else {
            dismiss()
        }
    }

    private func validateYatteeServerCredentials(url: URL, username: String, password: String, appEnvironment: AppEnvironment) async -> Bool {
        let client: HTTPClient
        if allowInvalidCertificates {
            client = appEnvironment.httpClientFactory.createClient(allowInvalidCertificates: true)
        } else {
            client = appEnvironment.httpClient
        }

        let credentials = "\(username):\(password)"
        guard let credentialData = credentials.data(using: .utf8) else { return false }
        let authHeader = "Basic \(credentialData.base64EncodedString())"

        let endpoint = GenericEndpoint.get("/info", customHeaders: ["Authorization": authHeader])

        do {
            let response: YatteeServerInfoValidation = try await client.fetch(endpoint, baseURL: url)
            return response.version != nil
        } catch {
            return false
        }
    }
}

// MARK: - Yattee Server Validation Response

private struct YatteeServerInfoValidation: Decodable {
    let name: String?
    let version: String?
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AddRemoteServerView()
            .appEnvironment(.preview)
    }
}
