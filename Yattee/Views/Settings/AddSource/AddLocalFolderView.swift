//
//  AddLocalFolderView.swift
//  Yattee
//
//  View for adding a local folder as a media source.
//

import SwiftUI

#if !os(tvOS)
struct AddLocalFolderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    // MARK: - State

    @State private var name = ""
    @State private var selectedFolderURL: URL?
    @State private var testResult: SourceTestResult?

    #if os(iOS)
    @State private var showingFolderPicker = false
    #endif

    // Closure to dismiss the parent sheet
    var dismissSheet: DismissAction?

    // MARK: - Computed Properties

    private var canAdd: Bool {
        !name.isEmpty && selectedFolderURL != nil
    }

    // MARK: - Body

    var body: some View {
        Form {
            nameSection
            folderSection

            if let result = testResult {
                SourceTestResultSection(result: result)
            }

            actionSection
        }
        .navigationTitle(String(localized: "sources.addLocalFolder"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingFolderPicker) {
            FolderPickerView { url in
                handleFolderSelection(url)
            }
        }
        #endif
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section {
            TextField(String(localized: "sources.field.name"), text: $name)
        } footer: {
            Text(String(localized: "sources.footer.displayName"))
        }
    }

    private var folderSection: some View {
        Section {
            #if os(iOS)
            Button {
                showingFolderPicker = true
            } label: {
                HStack {
                    if let url = selectedFolderURL {
                        Label(url.lastPathComponent, systemImage: "folder.fill")
                    } else {
                        Label(String(localized: "sources.selectFolder"), systemImage: "folder.badge.plus")
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
            #elseif os(macOS)
            Button {
                selectFolderMacOS()
            } label: {
                HStack {
                    if let url = selectedFolderURL {
                        Label(url.lastPathComponent, systemImage: "folder.fill")
                    } else {
                        Label(String(localized: "sources.selectFolder"), systemImage: "folder.badge.plus")
                    }
                    Spacer()
                }
            }
            #endif
        } header: {
            Text(String(localized: "sources.header.folder"))
        } footer: {
            Text(String(localized: "sources.footer.folder"))
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                addSource()
            } label: {
                Text(String(localized: "sources.addSource"))
            }
            .disabled(!canAdd)
        }
    }

    // MARK: - Actions

    private func handleFolderSelection(_ url: URL) {
        selectedFolderURL = url
        if name.isEmpty {
            name = url.lastPathComponent
        }
    }

    #if os(macOS)
    private func selectFolderMacOS() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            handleFolderSelection(url)
        }
    }
    #endif

    private func addSource() {
        guard let appEnvironment,
              let url = selectedFolderURL else { return }

        Task {
            do {
                let bookmarkData = try await appEnvironment.localFileClient.createBookmark(for: url)

                await MainActor.run {
                    let source = MediaSource.localFolder(
                        name: name,
                        url: url,
                        bookmarkData: bookmarkData
                    )
                    appEnvironment.mediaSourcesManager.add(source)
                    if let dismissSheet {
                        dismissSheet()
                    } else {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    testResult = .failure(String(localized: "sources.error.folderAccess \(error.localizedDescription)"))
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AddLocalFolderView()
            .appEnvironment(.preview)
    }
}
#endif
