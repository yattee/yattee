//
//  SourcesListView.swift
//  Yattee
//
//  Unified list of all sources (remote servers, WebDAV, local folders).
//

import SwiftUI

struct SourcesListView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var showingAddSheet = false
    @State private var sourceToEdit: UnifiedSource?

    // Delete confirmation state
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

    private var listStyle: VideoListStyle {
        appEnvironment?.settingsManager.listStyle ?? .inset
    }

    private var isEmpty: Bool {
        (instancesManager?.instances.isEmpty ?? true) &&
        (mediaSourcesManager?.isEmpty ?? true)
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
                        .accessibilityIdentifier("sources.addButton")
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    .focusSection()

                    sourcesInner
                        .focusSection()
                }
            }
            #elseif os(macOS)
            VStack(spacing: 0) {
                // macOS 15 does not surface a detail-pane NavigationStack's
                // toolbar items to the window title bar, so the toolbar
                // "Add Source" button is invisible there. Show an inline
                // header button as a fallback on older macOS. On macOS 26+
                // the toolbar button works, so this header is omitted.
                macOSLegacyAddHeader
                sourcesInner
            }
            #else
            sourcesInner
            #endif
        }
        #if !os(tvOS)
        .navigationTitle(String(localized: "sources.title"))
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(iOS) || os(macOS)
        .toolbar {
            if showAddButtonInToolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label(String(localized: "sources.addSource"), systemImage: "plus")
                    }
                    .accessibilityIdentifier("sources.addButton")
                }
            }
        }
        #endif
        #if os(tvOS)
        .navigationDestination(isPresented: $showingAddSheet) {
            TVSidebarDetailContainer(systemImage: "plus.circle", title: String(localized: "sources.newSource")) { AddSourceView() }
        }
        #else
        .sheet(isPresented: $showingAddSheet) {
            AddSourceView()
        }
        #endif
        #if os(tvOS)
        .navigationDestination(item: $sourceToEdit) { source in
            TVSidebarDetailContainer(systemImage: "pencil.circle", title: String(localized: "sources.editSource")) { EditSourceView(source: source) }
        }
        #else
        .sheet(item: $sourceToEdit) { source in
            EditSourceView(source: source)
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
        }
        #if !os(tvOS)
        .presentationCompactAdaptation(.sheet)
        #endif
    }

    /// Whether the "Add Source" button should be placed in the window/navigation
    /// toolbar. On macOS this only works reliably from macOS 26 onward (see
    /// `macOSLegacyAddHeader`); iOS always uses the toolbar.
    private var showAddButtonInToolbar: Bool {
        #if os(iOS)
        return true
        #elseif os(macOS)
        if #available(macOS 26, *) {
            return true
        } else {
            return false
        }
        #else
        return false
        #endif
    }

    #if os(macOS)
    // Inline fallback "Add Source" button for macOS versions where the
    // detail-pane toolbar item is not shown (pre-macOS 26). Only needed when
    // there are existing sources — the empty state already offers its own
    // add button.
    @ViewBuilder
    private var macOSLegacyAddHeader: some View {
        if !showAddButtonInToolbar, !isEmpty {
            HStack {
                Spacer()
                Button {
                    showingAddSheet = true
                } label: {
                    Label(String(localized: "sources.addSource"), systemImage: "plus")
                }
                .accessibilityIdentifier("sources.addButton")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
    }
    #endif

    @ViewBuilder
    private var sourcesInner: some View {
        if isEmpty {
            emptyState
        } else {
            sourcesList
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
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
        .accessibilityIdentifier("sources.view")
    }

    // MARK: - Sources List

    private var sourcesList: some View {
        (listStyle == .inset ? ListBackgroundStyle.grouped.color : ListBackgroundStyle.plain.color)
            .ignoresSafeArea()
            .overlay(
                ScrollView {
                    LazyVStack(spacing: 0) {
                        remoteServersSection
                        fileSourcesSection
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

    // MARK: - Section Header

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

    // MARK: - Section Card

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
            #if os(tvOS)
            .padding(.horizontal, 16)
            #else
            .background(ListBackgroundStyle.card.color)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            #endif
            .padding(.bottom, 16)
        } else {
            LazyVStack(spacing: 0) {
                content()
            }
            .padding(.bottom, 16)
        }
        #endif
    }

    // MARK: - Remote Servers Section

    @ViewBuilder
    private var remoteServersSection: some View {
        if let manager = instancesManager, !manager.instances.isEmpty {
            sectionHeader(String(localized: "sources.section.remoteServers"))

            let instances = manager.instances.sorted { $0.dateAdded < $1.dateAdded }

            sectionCard {
                ForEach(Array(instances.enumerated()), id: \.element.id) { index, instance in
                    let isLast = index == instances.count - 1
                    instanceRowView(instance, isLast: isLast, isFirst: index == 0)
                }
            }
        }
    }

    @ViewBuilder
    private func instanceRowView(_ instance: Instance, isLast: Bool, isFirst: Bool = false) -> some View {
        #if os(tvOS)
        SourceListRow(isLast: isLast, listStyle: listStyle) {
            Button {
                sourceToEdit = .remoteServer(instance)
            } label: {
                instanceRow(instance)
            }
            .foregroundStyle(.primary)
        }
        .modifier(FirstRowFocusModifier(isFirst: isFirst, focus: $firstSourceFocused))
        #else
        SourceListRow(isLast: isLast, listStyle: listStyle) {
            Button {
                sourceToEdit = .remoteServer(instance)
            } label: {
                instanceRow(instance)
            }
            #if os(macOS)
            .buttonStyle(.plain)
            #else
            .foregroundStyle(.primary)
            #endif
        }
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
        #endif
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
                HStack {
                    Text(instance.displayName)
                        .font(titleFont)
                        .foregroundStyle(.primary)

                    if !instance.isEnabled {
                        disabledBadge
                    }
                }

                Text("\(instance.type.displayName) - \(instance.url.host ?? instance.url.absoluteString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                instanceStatusView(for: instance)
            }

            Spacer()

            #if !os(macOS)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
            #endif
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func instanceStatusView(for instance: Instance) -> some View {
        if let status = instancesManager?.status(for: instance) {
            switch status {
            case .authFailed:
                Label(String(localized: "sources.status.authFailed"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            case .authRequired:
                Label(String(localized: "sources.status.authRequired"), systemImage: "key.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            default:
                EmptyView()
            }
        }
    }

    // MARK: - File Sources Section

    @ViewBuilder
    private var fileSourcesSection: some View {
        let allFileSources = allMediaSources
        let noRemoteServers = instancesManager?.instances.isEmpty ?? true
        if !allFileSources.isEmpty {
            sectionHeader(String(localized: "sources.section.fileSources"))

            sectionCard {
                ForEach(Array(allFileSources.enumerated()), id: \.element.id) { index, source in
                    let isLast = index == allFileSources.count - 1
                    fileSourceRowView(source, isLast: isLast, isFirst: noRemoteServers && index == 0)
                }
            }
        }
    }

    private var allMediaSources: [MediaSource] {
        guard let manager = mediaSourcesManager else { return [] }
        var sources: [MediaSource] = []
        sources.append(contentsOf: manager.webdavSources)
        sources.append(contentsOf: manager.smbSources)
        #if !os(tvOS)
        sources.append(contentsOf: manager.localFolderSources)
        #endif
        return sources.sorted { $0.dateAdded < $1.dateAdded }
    }

    @ViewBuilder
    private func fileSourceRowView(_ source: MediaSource, isLast: Bool, isFirst: Bool = false) -> some View {
        let needsPassword = mediaSourcesManager?.needsPassword(for: source) ?? false

        #if os(tvOS)
        SourceListRow(isLast: isLast, listStyle: listStyle) {
            Button {
                sourceToEdit = .fileSource(source)
            } label: {
                mediaSourceRow(source, needsPassword: needsPassword)
            }
            .foregroundStyle(.primary)
        }
        .modifier(FirstRowFocusModifier(isFirst: isFirst, focus: $firstSourceFocused))
        #else
        SourceListRow(isLast: isLast, listStyle: listStyle) {
            Button {
                sourceToEdit = .fileSource(source)
            } label: {
                mediaSourceRow(source, needsPassword: needsPassword)
            }
            #if os(macOS)
            .buttonStyle(.plain)
            #else
            .foregroundStyle(.primary)
            #endif
        }
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
        #endif
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
                HStack {
                    Text(source.name)
                        .font(titleFont)
                        .foregroundStyle(.primary)

                    if !source.isEnabled {
                        disabledBadge
                    }
                }

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
                .foregroundStyle(.tertiary)
            #endif
        }
        .contentShape(Rectangle())
    }

    // MARK: - Disabled Badge

    private var disabledBadge: some View {
        Text(String(localized: "sources.status.disabled"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary)
            .clipShape(Capsule())
    }

    // MARK: - Actions

    private func confirmDelete() {
        if let instance = pendingDeleteInstance, let manager = instancesManager {
            manager.remove(instance)
            pendingDeleteInstance = nil
        }

        if let source = pendingDeleteSource, let manager = mediaSourcesManager {
            manager.remove(source)
            pendingDeleteSource = nil
        }
    }

    private var deleteConfirmationMessage: String {
        if let instance = pendingDeleteInstance {
            return String(localized: "sources.delete.confirmation.single \(instance.displayName)")
        } else if let source = pendingDeleteSource {
            return String(localized: "sources.delete.confirmation.single \(source.name)")
        }
        return String(localized: "sources.delete.confirmation")
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
        SourcesListView()
    }
    .appEnvironment(.preview)
}
