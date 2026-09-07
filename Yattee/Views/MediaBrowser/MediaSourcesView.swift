//
//  MediaSourcesView.swift
//  Yattee
//
//  View for browsing all configured sources (instances and media sources).
//

import SwiftUI

struct MediaSourcesView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var sourceToEdit: UnifiedSource?
    @State private var showingAddSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var pendingDeleteInstance: Instance?
    @State private var pendingDeleteSource: MediaSource?

    #if os(tvOS)
    @FocusState private var firstSourceFocused: Bool
    #endif

    private var instancesManager: InstancesManager? {
        appEnvironment?.instancesManager
    }

    private var mediaSourcesManager: MediaSourcesManager? {
        appEnvironment?.mediaSourcesManager
    }

    private var sourcesSettings: SourcesSettings? {
        appEnvironment?.sourcesSettings
    }

    /// Whether there is nothing here at all — not merely nothing switched on.
    ///
    /// A user whose only source is disabled has sources; offering them the
    /// "add your first source" screen would be wrong, and would hide the one
    /// control that gets them back.
    private var isEmpty: Bool {
        (instancesManager?.enabledInstances.isEmpty ?? true) &&
        (mediaSourcesManager?.enabledSources.isEmpty ?? true) &&
        disabledInstances.isEmpty &&
        disabledMediaSources.isEmpty
    }

    private var listStyle: VideoListStyle {
        appEnvironment?.settingsManager.listStyle ?? .inset
    }

    /// Whether a remote server instance requires credentials that are missing from
    /// the Keychain (e.g. after reinstalling and importing sources from iCloud).
    private func needsCredentials(_ instance: Instance) -> Bool {
        appEnvironment?.needsCredentials(for: instance) ?? false
    }

    var body: some View {
        Group {
            #if os(tvOS)
            TVSidebarDetailContainer(
                systemImage: "server.rack",
                title: String(localized: "sources.title")
            ) {
                VStack(spacing: 0) {
                    HStack(spacing: 24) {
                        Button {
                            showingAddSheet = true
                        } label: {
                            Label(String(localized: "sources.addSource"), systemImage: "plus")
                        }
                        if let settings = sourcesSettings {
                            sortAndGroupMenu(settings)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    .focusSection()

                    mediaSourcesInner
                        .focusSection()
                }
            }
            #else
            mediaSourcesInner
            #endif
        }
        #if !os(tvOS)
        .navigationTitle(String(localized: "sources.title"))
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label(String(localized: "sources.addSource"), systemImage: "plus")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if let settings = sourcesSettings {
                    sortAndGroupMenu(settings)
                }
            }
        }
        #endif
        #if os(tvOS)
        .navigationDestination(item: $sourceToEdit) { source in
            TVSidebarDetailContainer(systemImage: "pencil.circle", title: String(localized: "sources.editSource")) {
                EditSourceView(source: source)
            }
        }
        .navigationDestination(isPresented: $showingAddSheet) {
            TVSidebarDetailContainer(systemImage: "plus.circle", title: String(localized: "sources.newSource")) {
                AddSourceView()
            }
        }
        #else
        .sheet(item: $sourceToEdit) { source in
            EditSourceView(source: source)
        }
        .sheet(isPresented: $showingAddSheet) {
            AddSourceView()
        }
        #endif
        .confirmationDialog(
            deleteConfirmationMessage,
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                confirmDelete()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {
                pendingDeleteInstance = nil
                pendingDeleteSource = nil
            }
        } message: {
            // The same cascade runs from here as from Settings, so the same
            // logins go with it — this dialog was simply the one still silent
            // about it.
            if let accounts = deleteConfirmationAccounts {
                Text(accounts)
            }
        }
        #if !os(tvOS)
        .presentationCompactAdaptation(.sheet)
        #endif
    }

    @ViewBuilder
    private var mediaSourcesInner: some View {
        if isEmpty {
            ContentUnavailableView {
                Label(String(localized: "sources.empty.title"), systemImage: "server.rack")
            } description: {
                Text(String(localized: "sources.empty.description"))
            } actions: {
                Button(String(localized: "sources.addSource")) {
                    showingAddSheet = true
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            sourcesList
        }
    }

    // MARK: - Private

    private var deleteConfirmationMessage: String {
        if let instance = pendingDeleteInstance {
            return String(localized: "sources.delete.confirmation.single \(instance.displayName)")
        } else if let source = pendingDeleteSource {
            return String(localized: "sources.delete.confirmation.single \(source.name)")
        }
        return String(localized: "sources.delete.confirmation")
    }

    private var deleteConfirmationAccounts: String? {
        guard let instance = pendingDeleteInstance else { return nil }
        return InstanceDeletionDisclosure.message(for: instance, in: appEnvironment)
    }

    private func confirmDelete() {
        if let instance = pendingDeleteInstance {
            appEnvironment?.removeInstance(instance)
            pendingDeleteInstance = nil
        }
        if let source = pendingDeleteSource {
            mediaSourcesManager?.remove(source)
            pendingDeleteSource = nil
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        #if os(macOS)
        Text(title)
            .font(.subheadline)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
        #else
        Text(title)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, listStyle == .inset ? 32 : 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
        #endif
    }

    private var sourcesList: some View {
        (listStyle == .inset ? ListBackgroundStyle.grouped.color : ListBackgroundStyle.plain.color)
            .ignoresSafeArea()
            .overlay(
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if let settings = sourcesSettings, !settings.groupByType {
                            // Ungrouped: All sources in one section
                            allSourcesSection(settings)
                        } else {
                            // Grouped by type (default)
                            groupedSourcesSections
                        }

                        disabledSourcesSection
                    }
                }
            )
            #if os(tvOS)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    firstSourceFocused = true
                }
            }
            #endif
    }

    @ViewBuilder
    private var groupedSourcesSections: some View {
        let settings = sourcesSettings
        let hasInstances = !(instancesManager?.enabledInstances.isEmpty ?? true)

        // Instances section
        if let manager = instancesManager, !manager.enabledInstances.isEmpty {
            sectionHeader(String(localized: "sources.section.remoteServers"))

            let sortedInstances = settings?.sorted(manager.enabledInstances) ?? manager.enabledInstances
            sectionCard {
                instancesSectionContent(sortedInstances, firstIsGlobalFirst: true)
            }
        }

        // Media sources section
        if let manager = mediaSourcesManager, !manager.enabledSources.isEmpty {
            sectionHeader(String(localized: "sources.section.fileSources"))

            let sortedSources = settings?.sorted(manager.enabledSources) ?? manager.enabledSources
            sectionCard {
                fileSourcesSectionContent(sortedSources, firstIsGlobalFirst: !hasInstances)
            }
        }
    }

    @ViewBuilder
    private func allSourcesSection(_ settings: SourcesSettings) -> some View {
        let sortedSources = allUnifiedSources(settings: settings)

        if !sortedSources.isEmpty {
            sectionHeader(String(localized: "sources.section.allSources"))

            sectionCard {
                ForEach(Array(sortedSources.enumerated()), id: \.element.id) { index, item in
                    let isLast = index == sortedSources.count - 1
                    let isFirst = index == 0

                    switch item {
                    case .instance(let instance):
                        instanceRowView(instance, isLast: isLast, isFirst: isFirst)
                    case .mediaSource(let source):
                        fileSourceRowView(source, isLast: isLast, isFirst: isFirst)
                    }
                }
            }
        }
    }

    private func allUnifiedSources(settings: SourcesSettings) -> [UnifiedSourceItem] {
        let instances = instancesManager?.enabledInstances ?? []
        let mediaSources = mediaSourcesManager?.enabledSources ?? []

        var allSources: [UnifiedSourceItem] = []
        allSources.append(contentsOf: instances.map { UnifiedSourceItem.instance($0) })
        allSources.append(contentsOf: mediaSources.map { UnifiedSourceItem.mediaSource($0) })

        return sortUnifiedSources(allSources, settings: settings)
    }

    private func sortUnifiedSources(_ sources: [UnifiedSourceItem], settings: SourcesSettings) -> [UnifiedSourceItem] {
        sources.sorted { first, second in
            let comparison: Bool
            switch settings.sortOption {
            case .name:
                comparison = first.displayName.localizedCaseInsensitiveCompare(second.displayName) == .orderedAscending
            case .type:
                comparison = first.typeDisplayName.localizedCaseInsensitiveCompare(second.typeDisplayName) == .orderedAscending
            case .dateAdded:
                comparison = first.dateAdded < second.dateAdded
            }
            return settings.sortDirection == .ascending ? comparison : !comparison
        }
    }

    // MARK: - Sort and Group Menu

    @ViewBuilder
    private func sortAndGroupMenu(_ settings: SourcesSettings) -> some View {
        Menu {
            // Sort options
            Section {
                Picker(selection: Binding(
                    get: { settings.sortOption },
                    set: { settings.sortOption = $0 }
                )) {
                    ForEach(settings.availableSortOptions, id: \.self) { option in
                        Label(option.displayName, systemImage: option.systemImage)
                            .tag(option)
                    }
                } label: {
                    Label(String(localized: "sources.sort.title"), systemImage: "arrow.up.arrow.down")
                }

                // Sort direction
                Button {
                    settings.sortDirection.toggle()
                } label: {
                    Label(
                        settings.sortDirection == .ascending
                            ? String(localized: "sources.sort.ascending")
                            : String(localized: "sources.sort.descending"),
                        systemImage: settings.sortDirection.systemImage
                    )
                }
            }

            // Grouping
            Section {
                Toggle(isOn: Binding(
                    get: { settings.groupByType },
                    set: {
                        settings.groupByType = $0
                        // Reset to name sort if type sort was selected and grouping is now enabled
                        if $0 && settings.sortOption == .type {
                            settings.sortOption = .name
                        }
                    }
                )) {
                    Label(String(localized: "sources.groupByType"), systemImage: "rectangle.3.group")
                }
            }
        } label: {
            Label(String(localized: "sources.sortAndGroup"), systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        #if os(macOS)
        VStack(spacing: 0) {
            Divider()
            LazyVStack(spacing: 0) {
                content()
            }
            Divider()
        }
        .padding(.bottom, 12)
        #else
        if listStyle == .inset {
            LazyVStack(spacing: 0) {
                content()
            }
            .background(ListBackgroundStyle.card.color)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        } else {
            LazyVStack(spacing: 0) {
                content()
            }
            .padding(.bottom, 16)
        }
        #endif
    }

    // MARK: - Disabled Sources

    /// The sources switched off, and the way back on.
    ///
    /// Every listing above is filtered to what is enabled, so switching a
    /// source off makes it vanish from the only screen that browses it — and
    /// the toggle that undoes it lives several taps away in Settings. This
    /// section is that toggle, kept at the bottom where it stays out of the way
    /// until it is the thing being looked for.
    @ViewBuilder
    private var disabledSourcesSection: some View {
        let instances = disabledInstances
        let sources = disabledMediaSources

        if !instances.isEmpty || !sources.isEmpty {
            sectionHeader(String(localized: "sources.status.disabled"))
                .accessibilityIdentifier("sources.disabledSection")

            sectionCard {
                ForEach(Array(instances.enumerated()), id: \.element.id) { index, instance in
                    disabledRow(
                        name: instance.displayName,
                        detail: "\(instance.type.displayName) - \(instance.url.host ?? instance.url.absoluteString)",
                        systemImage: instance.type.systemImage,
                        isLast: sources.isEmpty && index == instances.count - 1
                    ) {
                        instancesManager?.toggleEnabled(instance)
                    }
                }

                ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                    disabledRow(
                        name: source.name,
                        detail: "\(source.type.displayName) - \(source.urlDisplayString)",
                        systemImage: source.type.systemImage,
                        isLast: index == sources.count - 1
                    ) {
                        mediaSourcesManager?.toggleEnabled(source)
                    }
                }
            }

            Text(String(localized: "sources.disabled.footer"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                #if os(macOS)
                .padding(.horizontal, 16)
                #else
                .padding(.horizontal, listStyle == .inset ? 32 : 16)
                #endif
                .padding(.bottom, 16)
        }
    }

    /// Oldest first, matching the order every other listing settles into.
    private var disabledInstances: [Instance] {
        (instancesManager?.instances ?? [])
            .filter { !$0.isEnabled }
            .sorted { $0.dateAdded < $1.dateAdded }
    }

    private var disabledMediaSources: [MediaSource] {
        (mediaSourcesManager?.sources ?? [])
            .filter { !$0.isEnabled }
            .sorted { $0.dateAdded < $1.dateAdded }
    }

    /// A source that is off: dimmed, and tappable only to turn it back on.
    private func disabledRow(
        name: String,
        detail: String,
        systemImage: String,
        isLast: Bool,
        enable: @escaping () -> Void
    ) -> some View {
        #if os(tvOS)
        let rowSpacing: CGFloat = 24
        #else
        let rowSpacing: CGFloat = 12
        #endif
        #if os(macOS)
        let iconFont: Font = .title3
        let iconFrameWidth: CGFloat = 24
        let titleFont: Font = .body
        #else
        let iconFont: Font = .title2
        let iconFrameWidth: CGFloat = 32
        let titleFont: Font = .headline
        #endif

        return SourceListRow(isLast: isLast, listStyle: listStyle) {
            Button(action: enable) {
                HStack(spacing: rowSpacing) {
                    Image(systemName: systemImage)
                        .font(iconFont)
                        .foregroundStyle(.secondary)
                        .frame(width: iconFrameWidth)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(titleFont)
                            .foregroundStyle(.secondary)

                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Label(String(localized: "sources.enable"), systemImage: "power")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
                .contentShape(Rectangle())
            }
            #if os(macOS)
            .buttonStyle(.plain)
            #else
            .foregroundStyle(.primary)
            #endif
        }
    }

    @ViewBuilder
    private func instancesSectionContent(_ instances: [Instance], firstIsGlobalFirst: Bool = false) -> some View {
        ForEach(Array(instances.enumerated()), id: \.element.id) { index, instance in
            let isLastInSection = index == instances.count - 1

            instanceRowView(instance, isLast: isLastInSection, isFirst: firstIsGlobalFirst && index == 0)
        }
    }

    @ViewBuilder
    private func instanceRowView(_ instance: Instance, isLast: Bool, isFirst: Bool = false) -> some View {
        SourceListRow(isLast: isLast, listStyle: listStyle) {
            NavigationLink(value: NavigationDestination.instanceBrowse(instance)) {
                instanceRow(instance)
            }
            #if os(macOS)
            .buttonStyle(.plain)
            #else
            .foregroundStyle(.primary)
            #endif
        }
        #if os(tvOS)
        .modifier(FirstRowFocusModifier(isFirst: isFirst, focus: $firstSourceFocused))
        #endif
        .swipeActions {
            SwipeAction(symbolImage: "pencil", tint: .white, background: .orange) { reset in
                sourceToEdit = .remoteServer(instance)
                reset()
            }
            SwipeAction(symbolImage: "trash", tint: .white, background: .red) { reset in
                pendingDeleteInstance = instance
                showingDeleteConfirmation = true
                reset()
            }
        }
        .contextMenu {
            Button {
                sourceToEdit = .remoteServer(instance)
            } label: {
                Label(String(localized: "common.edit"), systemImage: "pencil")
            }

            Button(role: .destructive) {
                pendingDeleteInstance = instance
                showingDeleteConfirmation = true
            } label: {
                Label(String(localized: "common.delete"), systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func fileSourcesSectionContent(_ sources: [MediaSource], firstIsGlobalFirst: Bool = false) -> some View {
        ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
            let isLastInSection = index == sources.count - 1

            fileSourceRowView(source, isLast: isLastInSection, isFirst: firstIsGlobalFirst && index == 0)
        }
    }

    @ViewBuilder
    private func fileSourceRowView(_ source: MediaSource, isLast: Bool, isFirst: Bool = false) -> some View {
        let needsPassword = mediaSourcesManager?.needsPassword(for: source) ?? false

        SourceListRow(isLast: isLast, listStyle: listStyle) {
            if needsPassword {
                Button {
                    sourceToEdit = .fileSource(source)
                } label: {
                    mediaSourceRow(source, needsPassword: true)
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #else
                .foregroundStyle(.primary)
                #endif
            } else {
                NavigationLink(value: NavigationDestination.mediaBrowser(source, path: "/")) {
                    mediaSourceRow(source, needsPassword: false)
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #else
                .foregroundStyle(.primary)
                #endif
            }
        }
        #if os(tvOS)
        .modifier(FirstRowFocusModifier(isFirst: isFirst, focus: $firstSourceFocused))
        #endif
        .swipeActions {
            SwipeAction(symbolImage: "pencil", tint: .white, background: .orange) { reset in
                sourceToEdit = .fileSource(source)
                reset()
            }
            SwipeAction(symbolImage: "trash", tint: .white, background: .red) { reset in
                pendingDeleteSource = source
                showingDeleteConfirmation = true
                reset()
            }
        }
        .contextMenu {
            Button {
                sourceToEdit = .fileSource(source)
            } label: {
                Label(String(localized: "common.edit"), systemImage: "pencil")
            }

            Button(role: .destructive) {
                pendingDeleteSource = source
                showingDeleteConfirmation = true
            } label: {
                Label(String(localized: "common.delete"), systemImage: "trash")
            }
        }
    }

    private func instanceRow(_ instance: Instance) -> some View {
        #if os(tvOS)
        let rowSpacing: CGFloat = 24
        #else
        let rowSpacing: CGFloat = 12
        #endif
        #if os(macOS)
        let iconFont: Font = .title3
        let iconFrameWidth: CGFloat = 24
        let titleFont: Font = .body
        #else
        let iconFont: Font = .title2
        let iconFrameWidth: CGFloat = 32
        let titleFont: Font = .headline
        #endif
        return HStack(spacing: rowSpacing) {
            Image(systemName: instance.type.systemImage)
                .font(iconFont)
                .foregroundStyle(.tint)
                .frame(width: iconFrameWidth)

            VStack(alignment: .leading, spacing: 2) {
                Text(instance.displayName)
                    .font(titleFont)
                    .foregroundStyle(.primary)

                Text("\(instance.type.displayName) - \(instance.url.host ?? instance.url.absoluteString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                instanceStatusView(for: instance)
            }

            Spacer()

            #if !os(macOS)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
            #endif
        }
        .contentShape(Rectangle())
    }

    /// What is wrong with this source, said once.
    ///
    /// A refused login comes first: it names one thing the user has to do, and
    /// two warnings stacked on one row say less than either alone. Reading the
    /// status here also puts this row inside the observation of
    /// `AccountsManager.accountStatuses`, so a verdict arriving from the API
    /// layer redraws it.
    @ViewBuilder
    private func instanceStatusView(for instance: Instance) -> some View {
        if hasRejectedAccount(instance) {
            Label(
                AccountStatusBadge.text(for: .credentialRejected),
                systemImage: "person.crop.circle.badge.exclamationmark"
            )
            .font(.caption2)
            .foregroundStyle(AccountStatusBadge.color(for: .credentialRejected))
        } else if needsCredentials(instance) {
            Label(String(localized: "sources.status.authRequired"), systemImage: "key.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }

    /// Whether one of this instance's logins is being refused by the server.
    ///
    /// `needsCredentials` only knows whether a secret is *there*, so a
    /// credential the server has started refusing looks perfectly healthy to
    /// it — and this is the screen the user browses their sources from.
    private func hasRejectedAccount(_ instance: Instance) -> Bool {
        guard let accountsManager = appEnvironment?.accountsManager else { return false }

        return accountsManager.accounts(forInstance: instance.id).contains {
            accountsManager.status(for: $0.id) == .credentialRejected
        }
    }

    private func mediaSourceRow(_ source: MediaSource, needsPassword: Bool) -> some View {
        #if os(tvOS)
        let rowSpacing: CGFloat = 24
        #else
        let rowSpacing: CGFloat = 12
        #endif
        #if os(macOS)
        let iconFont: Font = .title3
        let iconFrameWidth: CGFloat = 24
        let titleFont: Font = .body
        #else
        let iconFont: Font = .title2
        let iconFrameWidth: CGFloat = 32
        let titleFont: Font = .headline
        #endif
        return HStack(spacing: rowSpacing) {
            Image(systemName: source.type.systemImage)
                .font(iconFont)
                .foregroundStyle(.tint)
                .frame(width: iconFrameWidth)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(titleFont)
                    .foregroundStyle(.primary)

                Text("\(source.type.displayName) - \(source.urlDisplayString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if needsPassword {
                    Label(String(localized: "sources.status.authRequired"), systemImage: "key.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            #if !os(macOS)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
            #endif
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Unified Source Item

/// Unified wrapper for sorting instances and media sources together.
private enum UnifiedSourceItem: Identifiable {
    case instance(Instance)
    case mediaSource(MediaSource)

    var id: String {
        switch self {
        case .instance(let instance):
            return "instance-\(instance.id.uuidString)"
        case .mediaSource(let source):
            return "source-\(source.id.uuidString)"
        }
    }

    var displayName: String {
        switch self {
        case .instance(let instance):
            return instance.displayName
        case .mediaSource(let source):
            return source.name
        }
    }

    var typeDisplayName: String {
        switch self {
        case .instance(let instance):
            return instance.type.displayName
        case .mediaSource(let source):
            return source.type.displayName
        }
    }

    var dateAdded: Date {
        switch self {
        case .instance(let instance):
            return instance.dateAdded
        case .mediaSource(let source):
            return source.dateAdded
        }
    }
}

#if os(tvOS)
private struct FirstRowFocusModifier: ViewModifier {
    let isFirst: Bool
    var focus: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        if isFirst {
            content.focused(focus)
        } else {
            content
        }
    }
}
#endif

// MARK: - Preview

#Preview {
    NavigationStack {
        MediaSourcesView()
    }
    .appEnvironment(.preview)
}
