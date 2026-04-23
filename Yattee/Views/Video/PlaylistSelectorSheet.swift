//
//  PlaylistSelectorSheet.swift
//  Yattee
//
//  Sheet for selecting a playlist to add a video to.
//

import SwiftUI
import NukeUI

struct PlaylistSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    let video: Video

    @State private var playlists: [LocalPlaylist] = []
    @State private var showingNewPlaylist = false
    @State private var pendingPlaylistTitle: String?
    @State private var pendingPlaylistDescription: String?
    @State private var addedToPlaylist: LocalPlaylist?

    private var dataManager: DataManager? { appEnvironment?.dataManager }

    var body: some View {
        NavigationStack {
            List {
                // Warning for local folder videos
                if video.isFromLocalFolder {
                    Section {
                        Label {
                            Text(String(localized: "playlist.localFileWarning"))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // Only show playlist options if not from local folder
                if !video.isFromLocalFolder {
                    // Create new playlist section
                    Section {
                        Button {
                            showingNewPlaylist = true
                        } label: {
                            Label(
                                String(localized: "playlist.new"),
                                systemImage: "plus.circle"
                            )
                        }
                    }

                    // Existing playlists
                    if !playlists.isEmpty {
                        Section {
                            ForEach(playlists, id: \.id) { playlist in
                                PlaylistSelectionRow(
                                    playlist: playlist,
                                    video: video,
                                    wasAdded: addedToPlaylist?.id == playlist.id
                                ) {
                                    addVideoToPlaylist(playlist)
                                }
                            }
                        }
                    } else {
                        Section {
                            ContentUnavailableView {
                                Label(
                                    String(localized: "playlist.empty.title"),
                                    systemImage: "music.note.list"
                                )
                            } description: {
                                Text(String(localized: "playlist.empty.description"))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
            #if os(tvOS)
            .scrollClipDisabled()
            .padding(.horizontal, 40)
            .padding(.vertical, 24)
            #else
            .navigationTitle(String(localized: "playlist.addTo"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Label(String(localized: "common.close"), systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            #endif
            .sheet(isPresented: $showingNewPlaylist) {
                PlaylistFormSheet(mode: .create) { title, description in
                    pendingPlaylistTitle = title
                    pendingPlaylistDescription = description
                }
            }
            .onChange(of: pendingPlaylistTitle) { _, newValue in
                if newValue != nil {
                    createAndAddToPlaylist()
                }
            }
            .onAppear {
                loadPlaylists()
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func loadPlaylists() {
        playlists = dataManager?.playlists() ?? []
    }

    private func addVideoToPlaylist(_ playlist: LocalPlaylist) {
        guard let dataManager else { return }

        dataManager.addToPlaylist(video, playlist: playlist)
        addedToPlaylist = playlist

        // Auto-dismiss after a short delay to show the checkmark
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            dismiss()
        }
    }

    private func createAndAddToPlaylist() {
        guard let dataManager, let title = pendingPlaylistTitle else { return }

        let newPlaylist = dataManager.createPlaylist(title: title, description: pendingPlaylistDescription)
        dataManager.addToPlaylist(video, playlist: newPlaylist)
        pendingPlaylistTitle = nil
        pendingPlaylistDescription = nil
        addedToPlaylist = newPlaylist

        // Refresh list and auto-dismiss
        loadPlaylists()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            dismiss()
        }
    }
}

// MARK: - Playlist Selection Row

private struct PlaylistSelectionRow: View {
    let playlist: LocalPlaylist
    let video: Video
    let wasAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 12) {
                // Thumbnail
                LazyImage(url: playlist.thumbnailURL) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(.quaternary)
                            .overlay {
                                Image(systemName: "music.note.list")
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(width: 60, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.title)
                        .font(.body)
                        .foregroundStyle(.primary)

                    Text(String(localized: "playlist.videoCount \(playlist.videoCount)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Status
                if wasAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if playlist.contains(videoID: video.id.videoID) {
                    Text(String(localized: "playlist.alreadyAdded"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(playlist.contains(videoID: video.id.videoID) && !wasAdded)
    }
}

// MARK: - Preview

#Preview {
    PlaylistSelectorSheet(video: .preview)
        .appEnvironment(.preview)
}
