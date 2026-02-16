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

    // Yattee Server credentials
    @State private var yatteeServerUsername: String = ""
    @State private var yatteeServerPassword: String = ""

    // Invidious login state
    @State private var showLoginSheet = false
    @State private var isLoggedIn = false

    // Yattee Server validation
    @State private var showingYatteeServerWarning = false

    // Delete confirmation
    @State private var showingDeleteConfirmation = false

    // Yattee Server info
    @State private var serverInfo: InstanceDetectorModels.YatteeServerFullInfo?
    @State private var isLoadingServerInfo = false
    @State private var serverInfoError: String?

    // Connection testing
    @State private var isTesting = false
    @State private var testResult: RemoteServerTestResult?

    enum RemoteServerTestResult {
        case success
        case failure(String)
    }

    init(instance: Instance) {
        self.instance = instance
        _name = State(initialValue: instance.name ?? "")
        _isEnabled = State(initialValue: instance.isEnabled)
        _allowInvalidCertificates = State(initialValue: instance.allowInvalidCertificates)
        _proxiesVideos = State(initialValue: instance.proxiesVideos)
    }

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
                    Text(String(localized: "sources.editSource"))
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    Button(String(localized: "common.save")) {
                        saveChanges()
                    }
                    .buttonStyle(TVToolbarButtonStyle())
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 24)

                formContent
                .accessibilityIdentifier("editSource.view")
            }
            #else
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
            #endif
        }
    }

    private var formContent: some View {
        Form {
            Section {
                LabeledContent(String(localized: "sources.field.type"), value: instance.type.displayName)
                LabeledContent(String(localized: "sources.field.url"), value: instance.url.absoluteString)
            }

            Section {
                #if os(tvOS)
                TVSettingsTextField(title: String(localized: "sources.field.name"), text: $name)
                TVSettingsToggle(title: String(localized: "sources.field.enabled"), isOn: $isEnabled)
                #else
                TextField(String(localized: "sources.field.name"), text: $name)
                Toggle(String(localized: "sources.field.enabled"), isOn: $isEnabled)
                #endif
            }

            if instance.type == .yatteeServer {
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
                Section {
                    if isLoggedIn {
                        Button(role: .destructive) {
                            logout()
                        } label: {
                            Label(String(localized: "login.logout"), systemImage: "rectangle.portrait.and.arrow.forward")
                        }
                        #if os(tvOS)
                        .buttonStyle(TVSettingsButtonStyle())
                        #endif
                    } else {
                        Button {
                            showLoginSheet = true
                        } label: {
                            Label(String(localized: "login.loginToAccount"), systemImage: "person.badge.key")
                        }
                        #if os(tvOS)
                        .buttonStyle(TVSettingsButtonStyle())
                        #endif
                    }
                } header: {
                    Text(String(localized: "login.header.account"))
                } footer: {
                    if isLoggedIn {
                        Text(String(localized: "login.footer.loggedIn"))
                    } else {
                        Text(String(localized: "login.footer.loginBenefits"))
                    }
                }

                // Import section - show when logged in for Invidious and Piped instances
                if isLoggedIn && (instance.type == .invidious || instance.type == .piped) {
                    Section {
                        NavigationLink {
                            ImportSubscriptionsView(instance: instance)
                        } label: {
                            Label(String(localized: "sources.import.subscriptions"), systemImage: "person.2")
                        }
                        .accessibilityIdentifier("sources.import.subscriptions")

                        NavigationLink {
                            ImportPlaylistsView(instance: instance)
                        } label: {
                            Label(String(localized: "sources.import.playlists"), systemImage: "list.bullet.rectangle")
                        }
                        .accessibilityIdentifier("sources.import.playlists")
                    } header: {
                        Text(String(localized: "sources.header.import"))
                    }
                }
            }

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

            Section {
                Button {
                    testConnection()
                } label: {
                    if isTesting {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text(String(localized: "sources.testing"))
                        }
                    } else {
                        Label(String(localized: "sources.testConnection"), systemImage: "network")
                    }
                }
                .disabled(isTesting)
                #if os(tvOS)
                .buttonStyle(TVSettingsButtonStyle())
                #endif
            }

            if let result = testResult {
                testResultSection(result)
            }

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
        .confirmationDialog(
            String(localized: "sources.delete.confirmation.single \(instance.displayName)"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                appEnvironment?.instancesManager.remove(instance)
                dismiss()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $showLoginSheet) {
            InstanceLoginView(instance: instance) { credential in
                appEnvironment?.credentialsManager(for: instance)?.setCredential(credential, for: instance)
                isLoggedIn = true
            }
        }
        .onAppear {
            isLoggedIn = appEnvironment?.credentialsManager(for: instance)?.isLoggedIn(for: instance) ?? false

            // Load existing Yattee Server credentials
            if instance.type == .yatteeServer,
               let credentials = appEnvironment?.yatteeServerCredentialsManager.credentials(for: instance) {
                yatteeServerUsername = credentials.username
                yatteeServerPassword = credentials.password
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

    private func logout() {
        appEnvironment?.credentialsManager(for: instance)?.deleteCredential(for: instance)
        isLoggedIn = false
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
        var updated = instance
        updated.name = name.isEmpty ? nil : name
        updated.isEnabled = isEnabled
        updated.allowInvalidCertificates = allowInvalidCertificates
        updated.proxiesVideos = proxiesVideos

        // Save Yattee Server credentials if provided
        if instance.type == .yatteeServer && !yatteeServerUsername.isEmpty && !yatteeServerPassword.isEmpty {
            appEnvironment?.yatteeServerCredentialsManager.setCredentials(
                username: yatteeServerUsername,
                password: yatteeServerPassword,
                for: instance
            )
        }

        appEnvironment?.instancesManager.update(updated)
        dismiss()
    }

    private func testConnection() {
        guard let appEnvironment else { return }
        isTesting = true
        testResult = nil

        Task {
            do {
                _ = try await appEnvironment.contentService.popular(for: instance)
                await MainActor.run {
                    isTesting = false
                    testResult = .success
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    testResult = .failure(error.localizedDescription)
                }
            }
        }
    }

    @ViewBuilder
    private func testResultSection(_ result: RemoteServerTestResult) -> some View {
        Section {
            switch result {
            case .success:
                Label(String(localized: "sources.test.success"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failure(let error):
                Label(error, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
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
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var testProgress: String?
    @State private var hasExistingPassword = false
    @State private var showingDeleteConfirmation = false

    enum TestResult {
        case success
        case successWithBandwidth(BandwidthTestResult)
        case failure(String)
    }

    init(source: MediaSource) {
        self.source = source
        _name = State(initialValue: source.name)
        _isEnabled = State(initialValue: source.isEnabled)
        _username = State(initialValue: source.username ?? "")
        _password = State(initialValue: "")
        _allowInvalidCertificates = State(initialValue: source.allowInvalidCertificates)
    }

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
                    Text(String(localized: "sources.editSource"))
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    Button(String(localized: "common.save")) {
                        saveChanges()
                    }
                    .disabled(name.isEmpty)
                    .buttonStyle(TVToolbarButtonStyle())
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 24)

                formContent
            }
            .onAppear {
                hasExistingPassword = appEnvironment?.mediaSourcesManager.password(for: source) != nil
                smbProtocolVersion = source.smbProtocolVersion ?? .auto
            }
            #else
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
            #endif
        }
    }

    private var formContent: some View {
        Form {
            Section {
                #if os(tvOS)
                TVSettingsTextField(title: String(localized: "sources.field.name"), text: $name)
                TVSettingsToggle(title: String(localized: "sources.field.enabled"), isOn: $isEnabled)
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

                Section {
                    Button {
                        testConnection()
                    } label: {
                        if isTesting {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text(testProgress ?? String(localized: "sources.testing"))
                            }
                        } else {
                            Label(String(localized: "sources.testConnection"), systemImage: "speedometer")
                        }
                    }
                    .disabled(isTesting)
                    #if os(tvOS)
                    .buttonStyle(TVSettingsButtonStyle())
                    #endif
                }

                if let result = testResult {
                    testResultSection(result)
                }
            }

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
    }

    @ViewBuilder
    private func testResultSection(_ result: TestResult) -> some View {
        Section {
            switch result {
            case .success:
                Label(String(localized: "sources.status.connected"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .successWithBandwidth(let bandwidth):
                VStack(alignment: .leading, spacing: 4) {
                    Label(String(localized: "sources.status.connected"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if bandwidth.hasWriteAccess {
                        if let upload = bandwidth.formattedUploadSpeed {
                            Label(String(localized: "sources.bandwidth.upload \(upload)"), systemImage: "arrow.up.circle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let download = bandwidth.formattedDownloadSpeed {
                        Label(String(localized: "sources.bandwidth.download \(download)"), systemImage: "arrow.down.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !bandwidth.hasWriteAccess {
                        Label(String(localized: "sources.status.readOnly"), systemImage: "lock.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                    if let warning = bandwidth.warning {
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            case .failure(let error):
                Label(error, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private func testConnection() {
        guard let appEnvironment else { return }

        isTesting = true
        testResult = nil
        testProgress = nil

        let testPassword = password.isEmpty
            ? appEnvironment.mediaSourcesManager.password(for: source)
            : password

        var updatedSource = source
        updatedSource.username = username.isEmpty ? nil : username
        updatedSource.allowInvalidCertificates = allowInvalidCertificates

        // Use factory to create client with appropriate SSL settings
        let webDAVClient = appEnvironment.webDAVClientFactory.createClient(for: updatedSource)

        Task {
            do {
                let bandwidthResult = try await webDAVClient.testBandwidth(
                    source: updatedSource,
                    password: testPassword
                ) { status in
                    Task { @MainActor in
                        self.testProgress = status
                    }
                }
                await MainActor.run {
                    isTesting = false
                    testProgress = nil
                    testResult = .successWithBandwidth(bandwidthResult)
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
