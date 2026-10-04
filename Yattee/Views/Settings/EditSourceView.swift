//
//  EditSourceView.swift
//  Yattee
//
//  Unified sheet for editing any source type.
//

import SwiftUI

struct EditSourceView: View {
    let source: UnifiedSource

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        switch source {
        case .remoteServer(let instance):
            EditRemoteServerContent(instance: instance)
        case .fileSource(let mediaSource):
            EditFileSourceContent(source: mediaSource)
        }
    }
}

// MARK: - Remote Server Content

private struct EditRemoteServerContent: View {
    let instance: Instance

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var name: String
    @State private var isEnabled: Bool
    @State private var allowInvalidCertificates: Bool
    @State private var proxiesVideos: Bool

    // Piped serves its API and web frontend from separate hosts; browser-facing
    // actions (open in browser, copy link) use this URL when set.
    @State private var frontendURLString: String

    // HTTP Basic Auth credentials (for any instance type behind a reverse proxy;
    // required for Yattee Server, optional for Invidious/Piped/PeerTube).
    @State private var basicAuthUsername: String = ""
    @State private var basicAuthPassword: String = ""
    /// Tracks whether credentials existed when the view loaded, so we can detect
    /// "user cleared the fields" and delete the stored credentials on save.
    @State private var hadStoredBasicAuth: Bool = false

    // Account login state. `loginTarget` is non-nil while the sheet is up and
    // carries the account being signed into — nil inside it means "create one".
    @State private var loginTarget: AccountLoginTarget?
    @State private var isLoggedIn = false

    // Yattee Server validation
    @State private var showingYatteeServerWarning = false

    // Delete confirmation
    @State private var showingDeleteConfirmation = false

    // Yattee Server info
    @State private var serverInfo: InstanceDetectorModels.YatteeServerFullInfo?
    @State private var isLoadingServerInfo = false
    @State private var serverInfoError: String?

    init(instance: Instance) {
        self.instance = instance
        _name = State(initialValue: instance.name ?? "")
        _isEnabled = State(initialValue: instance.isEnabled)
        _allowInvalidCertificates = State(initialValue: instance.allowInvalidCertificates)
        _proxiesVideos = State(initialValue: instance.proxiesVideos)
        _frontendURLString = State(initialValue: instance.frontendURL?.absoluteString ?? "")
    }

    var body: some View {
        #if os(tvOS)
        formContent
            .accessibilityIdentifier("editSource.view")
        #else
        NavigationStack {
            formContent
                .navigationTitle(String(localized: "sources.editSource"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "common.cancel")) {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "common.save")) {
                            saveChanges()
                        }
                    }
                }
                .accessibilityIdentifier("editSource.view")
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 450)
        #endif
        #endif
    }

    private var formContent: some View {
        Form {
            Section {
                LabeledContent(String(localized: "sources.field.type"), value: instance.type.displayName)
                LabeledContent(String(localized: "sources.field.url"), value: instance.displayURL)
            }

            Section {
                #if os(tvOS)
                TVSettingsTextField(title: String(localized: "sources.field.name"), text: $name)
                TVSettingsToggle(title: String(localized: "sources.field.enabled"), isOn: $isEnabled)
                #elseif os(macOS)
                LabeledContent(String(localized: "sources.field.name")) {
                    TextField("", text: $name)
                }
                Toggle(String(localized: "sources.field.enabled"), isOn: $isEnabled)
                #else
                TextField(String(localized: "sources.field.name"), text: $name)
                Toggle(String(localized: "sources.field.enabled"), isOn: $isEnabled)
                #endif
            }

            if instance.type == .piped {
                Section {
                    #if os(tvOS)
                    TVSettingsTextField(title: String(localized: "sources.field.frontendURL"), text: $frontendURLString)
                    #elseif os(macOS)
                    LabeledContent(String(localized: "sources.field.frontendURL")) {
                        TextField("", text: $frontendURLString)
                            .autocorrectionDisabled()
                    }
                    #else
                    TextField(String(localized: "sources.field.frontendURL"), text: $frontendURLString)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    #endif
                } footer: {
                    Text(String(localized: "sources.footer.frontendURL"))
                }
            }

            if instance.type == .yatteeServer {
                // Server Info Section
                Section {
                    if isLoadingServerInfo {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text(String(localized: "sources.serverInfo.loading"))
                                .foregroundStyle(.secondary)
                        }
                    } else if let info = serverInfo {
                        LabeledContent(String(localized: "sources.field.serverVersion"), value: info.version ?? "—")
                        LabeledContent(String(localized: "sources.field.ytdlp"), value: info.dependencies?.ytDlp ?? "—")
                        LabeledContent(String(localized: "sources.field.ffmpeg"), value: info.dependencies?.ffmpeg ?? "—")
                        LabeledContent(String(localized: "sources.field.invidiousInstance"), value: invidiousDisplayValue(info))

                        // Extractors section
                        if info.config?.allowAllSitesForExtraction == true {
                            LabeledContent(String(localized: "sources.field.extractors"), value: String(localized: "sources.serverInfo.allSitesSupported"))
                        } else if let sites = info.sites, !sites.isEmpty {
                            #if os(tvOS)
                            LabeledContent(String(localized: "sources.field.extractors"), value: "\(sites.count)")
                            #else
                            DisclosureGroup(String(localized: "sources.serverInfo.enabledExtractors \(sites.count)")) {
                                ForEach(sites, id: \.name) { site in
                                    Text(site.name)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            #endif
                        } else {
                            LabeledContent(String(localized: "sources.field.extractors"), value: String(localized: "sources.serverInfo.noneConfigured"))
                        }
                    } else if let error = serverInfoError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text(String(localized: "sources.header.serverInfo"))
                }
            }

            if instance.supportsAuthentication {
                InstanceAccountsSection(instance: instance, loginTarget: $loginTarget)

                // Import section - each entry offered only where the backend
                // has something to import from.
                if isLoggedIn,
                   instance.type.accountCapabilities.supportsSubscriptions
                   || instance.type.accountCapabilities.supportsPlaylistReads {
                    Section {
                        if instance.type.accountCapabilities.supportsSubscriptions {
                            NavigationLink {
                                #if os(tvOS)
                                TVSidebarDetailContainer(
                                    systemImage: "person.2",
                                    title: String(localized: "sources.import.subscriptions"),
                                    showsDismissButton: true
                                ) {
                                    ImportSubscriptionsView(instance: instance)
                                }
                                #else
                                ImportSubscriptionsView(instance: instance)
                                #endif
                            } label: {
                                Label(String(localized: "sources.import.subscriptions"), systemImage: "person.2")
                            }
                            .accessibilityIdentifier("sources.import.subscriptions")
                        }

                        if instance.type.accountCapabilities.supportsPlaylistReads {
                            NavigationLink {
                                #if os(tvOS)
                                TVSidebarDetailContainer(
                                    systemImage: "list.bullet.rectangle",
                                    title: String(localized: "sources.import.playlists"),
                                    showsDismissButton: true
                                ) {
                                    ImportPlaylistsView(instance: instance)
                                }
                                #else
                                ImportPlaylistsView(instance: instance)
                                #endif
                            } label: {
                                Label(String(localized: "sources.import.playlists"), systemImage: "list.bullet.rectangle")
                            }
                            .accessibilityIdentifier("sources.import.playlists")
                        }
                    } header: {
                        Text(String(localized: "sources.header.import"))
                    }
                }
            }

            Section {
                if instance.supportsHTTPBasicAuthProxy {
                    #if os(tvOS)
                    TVSettingsTextField(title: String(localized: "sources.field.username"), text: $basicAuthUsername)
                    TVSettingsTextField(title: String(localized: "sources.field.password"), text: $basicAuthPassword, isSecure: true)
                    #elseif os(macOS)
                    LabeledContent(String(localized: "sources.field.username")) {
                        TextField("", text: $basicAuthUsername)
                            .textContentType(.username)
                            .autocorrectionDisabled()
                    }
                    LabeledContent(String(localized: "sources.field.password")) {
                        SecureField("", text: $basicAuthPassword)
                            .textContentType(.password)
                    }
                    #else
                    TextField(String(localized: "sources.field.username"), text: $basicAuthUsername)
                        .textContentType(.username)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()

                    SecureField(String(localized: "sources.field.password"), text: $basicAuthPassword)
                        .textContentType(.password)
                    #endif
                }

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
                if instance.supportsHTTPBasicAuthProxy {
                    Text(String(localized: instance.type == .yatteeServer ? "sources.footer.yatteeServerAuth" : "sources.footer.basicAuth"))
                    + Text(verbatim: "\n\n")
                    + Text(String(localized: "sources.footer.allowInvalidCertificates"))
                } else {
                    Text(String(localized: "sources.footer.allowInvalidCertificates"))
                }
            }

            if instance.supportsVideoProxying {
                Section {
                    #if os(tvOS)
                    TVSettingsToggle(
                        title: String(localized: "sources.field.proxiesVideos"),
                        isOn: $proxiesVideos
                    )
                    #else
                    Toggle(String(localized: "sources.field.proxiesVideos"), isOn: $proxiesVideos)
                    #endif
                } header: {
                    Text(String(localized: "sources.header.proxy"))
                } footer: {
                    Text(String(localized: "sources.footer.proxiesVideos"))
                }
            }

            #if os(tvOS)
            Section {
                Button {
                    saveChanges()
                } label: {
                    Label(String(localized: "common.save"), systemImage: "checkmark.circle")
                }
                .buttonStyle(TVSettingsButtonStyle())
            }
            #endif

            Section {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label(String(localized: "sources.deleteSource"), systemImage: "trash")
                }
                #if os(tvOS)
                .buttonStyle(TVSettingsButtonStyle())
                #endif
            }
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .opaqueSettingsFormBackground()
        .confirmationDialog(
            String(localized: "sources.delete.confirmation.single \(instance.displayName)"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                appEnvironment?.removeInstance(instance)
                dismiss()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            // Deleting a source has always taken its logins with it; only the
            // question was silent about it.
            if let accounts = InstanceDeletionDisclosure.message(for: instance, in: appEnvironment) {
                Text(accounts)
            }
        }
        .presentationCompactAdaptation(.sheet)
        .platformSheet(item: $loginTarget) { target in
            InstanceLoginView(instance: instance, initialUsername: storedUsername(for: target)) { credential, username in
                storeLogin(credential: credential, username: username, target: target)
            }
        }
        // Signing out happens in the accounts section below, which cannot reach
        // this state directly. Without this the authenticated import actions
        // stay on screen after the last account is removed, and then fail.
        .onReceive(NotificationCenter.default.publisher(for: .accountsDidChange)) { _ in
            isLoggedIn = appEnvironment?.isSignedIn(to: instance) ?? false
        }
        // A credential arriving over iCloud Keychain changes only the status,
        // and the authenticated import actions depend on it.
        .onReceive(NotificationCenter.default.publisher(for: .accountStatusesDidChange)) { _ in
            isLoggedIn = appEnvironment?.isSignedIn(to: instance) ?? false
        }
        .onAppear {
            isLoggedIn = appEnvironment?.isSignedIn(to: instance) ?? false

            // Load existing HTTP Basic Auth credentials (works for any instance type)
            if let credentials = appEnvironment?.basicAuthCredentialsManager.credentials(for: instance) {
                basicAuthUsername = credentials.username
                basicAuthPassword = credentials.password
                hadStoredBasicAuth = true
            }
        }
        .task {
            await loadServerInfo()
        }
        .confirmationDialog(
            String(localized: "sources.yatteeServer.warning.title"),
            isPresented: $showingYatteeServerWarning,
            titleVisibility: .visible
        ) {
            Button(String(localized: "sources.yatteeServer.warning.disableOthers"), role: .destructive) {
                appEnvironment?.instancesManager.disableOtherYatteeServerInstances(except: instance.id)
                performSave()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "sources.yatteeServer.warning.message"))
        }
        .presentationCompactAdaptation(.sheet)
    }

    // MARK: - Computed Properties

    private var hasYatteeServer: Bool {
        appEnvironment?.instancesManager.hasYatteeServerInstances ?? false
    }

    private func invidiousDisplayValue(_ info: InstanceDetectorModels.YatteeServerFullInfo) -> String {
        guard let invidiousInstance = info.config?.invidiousInstance else {
            return String(localized: "sources.serverInfo.notConfigured")
        }
        if invidiousInstance == "not configured" || invidiousInstance.isEmpty {
            return String(localized: "sources.serverInfo.notConfigured")
        }
        // Extract just the host from the URL for cleaner display
        if let url = URL(string: invidiousInstance), let host = url.host {
            return host
        }
        return invidiousInstance
    }

    // MARK: - Actions

    /// Files a successful login against an account, and reflects it in the
    /// authenticated actions this sheet shows.
    @discardableResult
    private func storeLogin(credential: String, username: String, target: AccountLoginTarget) -> Bool {
        guard let appEnvironment else { return false }

        let stored = AccountSignInHandler(appEnvironment: appEnvironment, instance: instance)
            .storeLogin(credential: credential, username: username, target: target)

        if stored {
            isLoggedIn = true
        }
        return stored
    }

    /// The identifier an existing account last signed in with, when this device
    /// holds it. A new account has nobody to name yet.
    private func storedUsername(for target: AccountLoginTarget) -> String? {
        guard let account = target.account else { return nil }
        return appEnvironment?.accountCredentialsManager(for: account)?.username(for: account)
    }

    private func loadServerInfo() async {
        guard instance.type == .yatteeServer, let appEnvironment else { return }

        isLoadingServerInfo = true
        serverInfoError = nil

        do {
            serverInfo = try await appEnvironment.contentService.yatteeServerInfo(for: instance)
        } catch {
            serverInfoError = String(localized: "sources.serverInfo.loadError")
        }

        isLoadingServerInfo = false
    }

    private func saveChanges() {
        // Check if we're enabling a Yattee Server instance
        let wasDisabled = !instance.isEnabled
        let willBeEnabled = isEnabled
        let isYatteeServer = instance.type == .yatteeServer

        if isYatteeServer && wasDisabled && willBeEnabled {
            let otherEnabled = appEnvironment?.instancesManager.enabledYatteeServerInstances ?? []
            if !otherEnabled.isEmpty {
                showingYatteeServerWarning = true
                return
            }
        }

        performSave()
    }

    private func performSave() {
        // Start from the manager's latest copy so flags updated while this sheet
        // was open (e.g. usesAccountLogin set by the login sheet) are preserved.
        var updated = appEnvironment?.instancesManager.instances.first { $0.id == instance.id } ?? instance
        updated.name = name.isEmpty ? nil : name
        updated.isEnabled = isEnabled
        updated.allowInvalidCertificates = allowInvalidCertificates
        updated.proxiesVideos = proxiesVideos

        if instance.type == .piped {
            let trimmed = frontendURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.frontendURL = trimmed.isEmpty ? nil : Instance.normalizeSourceURL(trimmed)
        }

        // Save / clear HTTP Basic Auth credentials. Yattee Server never auto-clears
        // (credentials are required and the user re-enters to overwrite). Piped never
        // persists them — its session token reuses the same Authorization header.
        if !instance.supportsHTTPBasicAuthProxy {
            if hadStoredBasicAuth {
                appEnvironment?.basicAuthCredentialsManager.deleteCredentials(for: instance)
            }
            updated.usesBasicAuth = false
        } else if !basicAuthUsername.isEmpty, !basicAuthPassword.isEmpty {
            appEnvironment?.basicAuthCredentialsManager.setCredentials(
                username: basicAuthUsername,
                password: basicAuthPassword,
                for: instance
            )
            updated.usesBasicAuth = true
        } else if hadStoredBasicAuth, instance.type != .yatteeServer {
            appEnvironment?.basicAuthCredentialsManager.deleteCredentials(for: instance)
            updated.usesBasicAuth = false
        }

        appEnvironment?.instancesManager.update(updated)
        dismiss()
    }
}

// MARK: - File Source Content

private struct EditFileSourceContent: View {
    let source: MediaSource

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var name: String
    @State private var isEnabled: Bool
    @State private var username: String
    @State private var password: String
    @State private var allowInvalidCertificates: Bool
    @State private var smbProtocolVersion: SMBProtocol = .auto
    @State private var hasExistingPassword = false
    @State private var showingDeleteConfirmation = false

    init(source: MediaSource) {
        self.source = source
        _name = State(initialValue: source.name)
        _isEnabled = State(initialValue: source.isEnabled)
        _username = State(initialValue: source.username ?? "")
        _password = State(initialValue: "")
        _allowInvalidCertificates = State(initialValue: source.allowInvalidCertificates)
    }

    var body: some View {
        #if os(tvOS)
        formContent
            .onAppear {
                hasExistingPassword = appEnvironment?.mediaSourcesManager.password(for: source) != nil
                smbProtocolVersion = source.smbProtocolVersion ?? .auto
            }
        #else
        NavigationStack {
            formContent
                .navigationTitle(String(localized: "sources.editSource"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "common.cancel")) {
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "common.save")) {
                            saveChanges()
                        }
                        .disabled(name.isEmpty)
                    }
                }
                .onAppear {
                    hasExistingPassword = appEnvironment?.mediaSourcesManager.password(for: source) != nil
                    smbProtocolVersion = source.smbProtocolVersion ?? .auto
                }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 450)
        #endif
        #endif
    }

    private var formContent: some View {
        Form {
            Section {
                #if os(tvOS)
                TVSettingsTextField(title: String(localized: "sources.field.name"), text: $name)
                TVSettingsToggle(title: String(localized: "sources.field.enabled"), isOn: $isEnabled)
                #elseif os(macOS)
                LabeledContent(String(localized: "sources.field.name")) {
                    TextField("", text: $name)
                }
                Toggle(String(localized: "sources.field.enabled"), isOn: $isEnabled)
                #else
                TextField(String(localized: "sources.field.name"), text: $name)
                Toggle(String(localized: "sources.field.enabled"), isOn: $isEnabled)
                #endif
            } header: {
                Text(String(localized: "sources.header.general"))
            }

            Section {
                HStack {
                    Text(String(localized: "sources.field.type"))
                    Spacer()
                    Label(source.type.displayName, systemImage: source.type.systemImage)
                        .foregroundStyle(.secondary)
                }
                #if !os(tvOS)
                .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
                #endif

                #if os(macOS)
                HStack {
                    Text(String(localized: "sources.field.url"))
                    Spacer()
                    Text(source.url.absoluteString)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                #else
                if source.type != .localFolder {
                    HStack {
                        Text(String(localized: "sources.field.url"))
                        Spacer()
                        Text(source.url.absoluteString)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                #endif
            }

            if source.type == .webdav || source.type == .smb {
                Section {
                    #if os(tvOS)
                    TVSettingsTextField(title: String(localized: "sources.field.username"), text: $username)
                    TVSettingsTextField(
                        title: hasExistingPassword
                            ? String(localized: "sources.field.passwordKeep")
                            : String(localized: "sources.field.passwordRequired"),
                        text: $password,
                        isSecure: true
                    )
                    #elseif os(macOS)
                    LabeledContent(String(localized: "sources.field.username")) {
                        TextField("", text: $username)
                            .textContentType(.username)
                            .autocorrectionDisabled()
                    }
                    LabeledContent(String(localized: "sources.field.password")) {
                        SecureField(
                            hasExistingPassword
                                ? String(localized: "sources.field.passwordKeep")
                                : String(localized: "sources.field.passwordRequired"),
                            text: $password
                        )
                        .textContentType(.password)
                    }
                    #else
                    TextField(String(localized: "sources.field.username"), text: $username)
                        .textContentType(.username)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()

                    SecureField(
                        hasExistingPassword
                            ? String(localized: "sources.field.passwordKeep")
                            : String(localized: "sources.field.passwordRequired"),
                        text: $password
                    )
                    .textContentType(.password)
                    #endif
                } header: {
                    Text(String(localized: "sources.header.auth"))
                }
            }

            if source.type == .smb {
                Section {
                    Picker(String(localized: "sources.field.smbProtocol"), selection: $smbProtocolVersion) {
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

            if source.type == .webdav {
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

            #if os(tvOS)
            Section {
                Button {
                    saveChanges()
                } label: {
                    Label(String(localized: "common.save"), systemImage: "checkmark.circle")
                }
                .disabled(name.isEmpty)
                .buttonStyle(TVSettingsButtonStyle())
            }
            #endif

            Section {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label(String(localized: "sources.deleteSource"), systemImage: "trash")
                        .foregroundStyle(.red)
                }
                #if os(tvOS)
                .buttonStyle(TVSettingsButtonStyle())
                #endif
            }
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .opaqueSettingsFormBackground()
        .confirmationDialog(
            String(localized: "sources.delete.confirmation.single \(source.name)"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                deleteSource()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
        .presentationCompactAdaptation(.sheet)
    }

    private func saveChanges() {
        guard let appEnvironment else { return }

        var updatedSource = source
        updatedSource.name = name
        updatedSource.isEnabled = isEnabled

        if source.type == .webdav || source.type == .smb {
            updatedSource.username = username.isEmpty ? nil : username

            if !password.isEmpty {
                appEnvironment.mediaSourcesManager.setPassword(password, for: source)
            }
        }

        if source.type == .webdav {
            updatedSource.allowInvalidCertificates = allowInvalidCertificates
        }

        if source.type == .smb {
            updatedSource.smbProtocolVersion = smbProtocolVersion

            // Clear SMB cache if credentials or protocol changed
            let credentialsChanged = (source.username != updatedSource.username) || !password.isEmpty
            let protocolChanged = source.smbProtocolVersion != smbProtocolVersion

            if credentialsChanged || protocolChanged {
                Task {
                    await appEnvironment.smbClient.clearCache(for: source)
                }
            }
        }

        appEnvironment.mediaSourcesManager.update(updatedSource)
        dismiss()
    }

    private func deleteSource() {
        guard let appEnvironment else { return }
        appEnvironment.mediaSourcesManager.remove(source)
        dismiss()
    }
}

// MARK: - Preview

#Preview("Remote Server") {
    EditSourceView(
        source: .remoteServer(Instance(type: .invidious, url: URL(string: "https://invidious.example.com")!))
    )
    .appEnvironment(.preview)
}

#Preview("WebDAV") {
    EditSourceView(
        source: .fileSource(.webdav(name: "My NAS", url: URL(string: "https://nas.local:5006")!, username: "user"))
    )
    .appEnvironment(.preview)
}
