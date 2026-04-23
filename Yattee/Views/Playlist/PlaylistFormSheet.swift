//
//  PlaylistFormSheet.swift
//  Yattee
//
//  Reusable form sheet for creating and editing playlists.
//

import SwiftUI

struct PlaylistFormSheet: View {
    enum Mode: Equatable {
        case create
        case edit(LocalPlaylist)

        static func == (lhs: Mode, rhs: Mode) -> Bool {
            switch (lhs, rhs) {
            case (.create, .create):
                return true
            case (.edit(let lhsPlaylist), .edit(let rhsPlaylist)):
                return lhsPlaylist.id == rhsPlaylist.id
            default:
                return false
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let onSave: (String, String?) -> Void

    @State private var title: String = ""
    @State private var descriptionText: String = ""

    private let maxDescriptionLength = 1000

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var navigationTitle: String {
        isEditing
            ? String(localized: "playlist.edit")
            : String(localized: "playlist.new")
    }

    private var saveButtonTitle: String {
        isEditing
            ? String(localized: "common.save")
            : String(localized: "common.create")
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            #if os(tvOS)
            tvOSContent
            #else
            formContent
                .navigationTitle(navigationTitle)
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
                        Button(saveButtonTitle) {
                            save()
                        }
                        .disabled(!canSave)
                    }
                }
            #endif
        }
        .onAppear {
            if case .edit(let playlist) = mode {
                title = playlist.title
                descriptionText = playlist.playlistDescription ?? ""
            }
        }
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }

    // MARK: - Form Content

    #if !os(tvOS)
    private var formContent: some View {
        Form {
            Section {
                TextField(String(localized: "playlist.name"), text: $title)
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    #endif
            } header: {
                Text(String(localized: "playlist.name"))
            }

            Section {
                TextEditor(text: $descriptionText)
                    .frame(minHeight: 100)
                    .onChange(of: descriptionText) { _, newValue in
                        if newValue.count > maxDescriptionLength {
                            descriptionText = String(newValue.prefix(maxDescriptionLength))
                        }
                    }
            } header: {
                Text(String(localized: "playlist.description"))
            } footer: {
                HStack {
                    Text(String(localized: "playlist.description.optional"))
                    Spacer()
                    Text("\(descriptionText.count)/\(maxDescriptionLength)")
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
            }
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }
    #endif

    // MARK: - tvOS Content

    #if os(tvOS)
    private var tvOSContent: some View {
        VStack(spacing: 0) {
            Text(navigationTitle)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .padding(.top, 16)

            Form {
                Section {
                    TVSettingsTextField(
                        title: String(localized: "playlist.name"),
                        text: $title
                    )
                } header: {
                    Text(String(localized: "playlist.name"))
                }

                Section {
                    TVSettingsTextField(
                        title: String(localized: "playlist.description.placeholder"),
                        text: $descriptionText
                    )
                } header: {
                    Text(String(localized: "playlist.description"))
                } footer: {
                    HStack {
                        Text(String(localized: "playlist.description.optional"))
                        Spacer()
                        Text("\(descriptionText.count)/\(maxDescriptionLength)")
                            .monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                }

                Section {
                    Button(saveButtonTitle) {
                        save()
                    }
                    .buttonStyle(TVToolbarButtonStyle())
                    .lineLimit(1)
                    .disabled(!canSave)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                }
            }
            .scrollClipDisabled()
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }
    #endif

    // MARK: - Actions

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)

        onSave(trimmedTitle, trimmedDescription.isEmpty ? nil : trimmedDescription)
        dismiss()
    }
}

// MARK: - Preview

#Preview("Create") {
    PlaylistFormSheet(mode: .create) { _, _ in }
}
