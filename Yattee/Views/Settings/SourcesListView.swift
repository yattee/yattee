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
            if isEmpty {
                emptyState
            } else {
                sourcesList
            }
        }
        .accessibilityIdentifier("sources.view")
        .navigationTitle(String(localized: "sources.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label(String(localized: "sources.addSource"), systemImage: "plus")
                }
                .accessibilityIdentifier("sources.addButton")
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddSourceView()
        }
        .sheet(item: $sourceToEdit) { source in
            EditSourceView(source: source)
        }
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
    }

    // MARK: - Section Header

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, listStyle == .inset ? 32 : 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }

    // MARK: - Section Card

    @ViewBuilder
    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
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
                    instanceRowView(instance, isLast: isLast)
                }
            }
        }
    }

    @ViewBuilder
    private func instanceRowView(_ instance: Instance, isLast: Bool) -> some View {
        #if os(tvOS)
        SourceListRow(isLast: isLast, listStyle: listStyle) {
            Button {
                sourceToEdit = .remoteServer(instance)
            } label: {
                instanceRow(instance)
            }
            .buttonStyle(.card)
        }
        #else
        SourceListRow(isLast: isLast, listStyle: listStyle) {
            Button {
                sourceToEdit = .remoteServer(instance)
            } label: {
                instanceRow(instance)
            }
            .foregroundStyle(.primary)
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
        HStack(spacing: 12) {
            Image(systemName: instance.type.systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(instance.displayName)
                        .font(.headline)
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

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
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
        if !allFileSources.isEmpty {
            sectionHeader(String(localized: "sources.section.fileSources"))

            sectionCard {
                ForEach(Array(allFileSources.enumerated()), id: \.element.id) { index, source in
                    let isLast = index == allFileSources.count - 1
                    fileSourceRowView(source, isLast: isLast)
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
    private func fileSourceRowView(_ source: MediaSource, isLast: Bool) -> some View {
        let needsPassword = mediaSourcesManager?.needsPassword(for: source) ?? false

        #if os(tvOS)
        SourceListRow(isLast: isLast, listStyle: listStyle) {
            Button {
                sourceToEdit = .fileSource(source)
            } label: {
                mediaSourceRow(source, needsPassword: needsPassword)
            }
            .buttonStyle(.card)
        }
        #else
        SourceListRow(isLast: isLast, listStyle: listStyle) {
            Button {
                sourceToEdit = .fileSource(source)
            } label: {
                mediaSourceRow(source, needsPassword: needsPassword)
            }
            .foregroundStyle(.primary)
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
        HStack(spacing: 12) {
            Image(systemName: source.type.systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(source.name)
                        .font(.headline)
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

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
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

// MARK: - Preview

#Preview {
    NavigationStack {
        SourcesListView()
    }
    .appEnvironment(.preview)
}
