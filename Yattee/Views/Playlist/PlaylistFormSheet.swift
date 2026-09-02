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
        /// Editing a playlist that lives on a server.
        ///
        /// Server-side playlists are plain values rather than models, so what to
        /// pre-fill is passed in. `privacy` is optional because the fetch does
        /// not always say what it is — Invidious returns no visibility with the
        /// playlist, so the picker falls back to its conservative default.
        case editRemote(title: String, description: String?, privacy: PlaylistPrivacy?)

        static func == (lhs: Mode, rhs: Mode) -> Bool {
            switch (lhs, rhs) {
            case (.create, .create):
                return true
            case (.edit(let lhsPlaylist), .edit(let rhsPlaylist)):
                return lhsPlaylist.id == rhsPlaylist.id
            case (.editRemote(let lhsTitle, let lhsDescription, let lhsPrivacy),
                  .editRemote(let rhsTitle, let rhsDescription, let rhsPrivacy)):
                return lhsTitle == rhsTitle && lhsDescription == rhsDescription && lhsPrivacy == rhsPrivacy
            default:
                return false
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    /// Whether the destination has a visibility setting to pick at all.
    ///
    /// Follows the destination account's capabilities: a backend without a
    /// visibility concept is never asked about one, and the write layer drops
    /// the value rather than inventing it.
    let showsPrivacy: Bool

    private let onSave: (String, String?, PlaylistPrivacy) -> Void

    /// Local playlists have no visibility, so their callers never see one.
    init(mode: Mode, onSave: @escaping (String, String?) -> Void) {
        self.mode = mode
        self.showsPrivacy = false
        self.onSave = { title, description, _ in onSave(title, description) }
    }

    /// Server-side playlists, where the caller is the one that talks to the
    /// account — this sheet still never touches a service.
    init(
        mode: Mode,
        showsPrivacy: Bool,
        privacy: PlaylistPrivacy = .private,
        onSaveWithPrivacy: @escaping (String, String?, PlaylistPrivacy) -> Void
    ) {
        self.mode = mode
        self.showsPrivacy = showsPrivacy
        self.onSave = onSaveWithPrivacy
        self._privacy = State(initialValue: privacy)
    }

    @State private var title: String = ""
    @State private var descriptionText: String = ""
    /// Private by default: the conservative choice, and the one Invidious makes.
    @State private var privacy: PlaylistPrivacy = .private

    private let maxDescriptionLength = 1000

    private var isEditing: Bool {
        switch mode {
        case .create: return false
        case .edit, .editRemote: return true
        }
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
            switch mode {
            case .create:
                break
            case .edit(let playlist):
                title = playlist.title
                descriptionText = playlist.playlistDescription ?? ""
            case .editRemote(let remoteTitle, let remoteDescription, let remotePrivacy):
                title = remoteTitle
                descriptionText = remoteDescription ?? ""
                // Only when the fetch actually said so — otherwise whatever the
                // caller preselected stands.
                if let remotePrivacy { privacy = remotePrivacy }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
    }

    // MARK: - Form Content

    #if !os(tvOS)
    private var formContent: some View {
        Form {
            Section {
                TextField(
                    String(localized: "playlist.name"),
                    text: $title,
                    prompt: Text(String(localized: "playlist.name"))
                )
                #if os(iOS)
                .textInputAutocapitalization(.sentences)
                #endif
                #if os(macOS)
                .labelsHidden()
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

            if showsPrivacy {
                Section {
                    privacyPicker
                } header: {
                    Text(String(localized: "playlist.privacy"))
                } footer: {
                    Text(String(localized: "playlist.privacy.footer"))
                }
            }
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        #if os(macOS)
        .formStyle(.grouped)
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

                if showsPrivacy {
                    Section {
                        privacyPicker
                    } header: {
                        Text(String(localized: "playlist.privacy"))
                    } footer: {
                        Text(String(localized: "playlist.privacy.footer"))
                    }
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

    // MARK: - Privacy

    private var privacyPicker: some View {
        Picker(String(localized: "playlist.privacy"), selection: $privacy) {
            ForEach(PlaylistPrivacy.allCases, id: \.self) { option in
                Text(Self.label(for: option)).tag(option)
            }
        }
        #if os(macOS)
        .labelsHidden()
        #endif
    }

    private static func label(for privacy: PlaylistPrivacy) -> String {
        switch privacy {
        case .public: String(localized: "playlist.privacy.public")
        case .unlisted: String(localized: "playlist.privacy.unlisted")
        case .private: String(localized: "playlist.privacy.private")
        }
    }

    // MARK: - Actions

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)

        onSave(trimmedTitle, trimmedDescription.isEmpty ? nil : trimmedDescription, privacy)
        dismiss()
    }
}

// MARK: - Preview

#Preview("Create") {
    PlaylistFormSheet(mode: .create) { _, _ in }
}
