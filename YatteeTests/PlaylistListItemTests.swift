//
//  PlaylistListItemTests.swift
//  YatteeTests
//
//  Tests for the playlists list's row model: identity, mapping and search.
//

import Testing
import Foundation
@testable import Yattee

@MainActor
@Suite("Playlist List Item")
struct PlaylistListItemTests {

    // MARK: - Helpers

    private static func remotePlaylist(
        id: String = "IVPL123",
        title: String = "Remote",
        description: String? = nil
    ) -> Playlist {
        Playlist(
            id: PlaylistID.global(id),
            title: title,
            description: description,
            videoCount: 3
        )
    }

    // MARK: - Identity

    @Test("Local identity is the playlist's own id")
    func localIdentity() {
        let playlist = LocalPlaylist(title: "Mine")
        let item = PlaylistListItem.local(playlist)

        #expect(item.id == .local(playlist.id))
    }

    @Test("Remote identity is the server-side id")
    func remoteIdentity() {
        let playlist = Self.remotePlaylist()
        let item = PlaylistListItem.remote(playlist)

        #expect(item.id == .remote(playlist.id))
    }

    @Test("Two rows of the same playlist share an identity")
    func identityIsStable() {
        let playlist = Self.remotePlaylist()

        #expect(PlaylistListItem.remote(playlist).id == PlaylistListItem.remote(playlist).id)
    }

    @Test("Different playlists never share an identity")
    func identityDistinguishesPlaylists() {
        let first = PlaylistListItem.remote(Self.remotePlaylist(id: "IVPL1"))
        let second = PlaylistListItem.remote(Self.remotePlaylist(id: "IVPL2"))
        let local = PlaylistListItem.local(LocalPlaylist(title: "Mine"))

        #expect(first.id != second.id)
        #expect(first.id != local.id)
    }

    // MARK: - Mapping

    @Test("Titles come from either side")
    func titles() {
        #expect(PlaylistListItem.local(LocalPlaylist(title: "Mine")).title == "Mine")
        #expect(PlaylistListItem.remote(Self.remotePlaylist(title: "Theirs")).title == "Theirs")
    }

    @Test("Descriptions come from either side, whatever they are called there")
    func descriptions() {
        let local = LocalPlaylist(title: "Mine", description: "on device")
        let remote = Self.remotePlaylist(description: "on server")

        #expect(PlaylistListItem.local(local).playlistDescription == "on device")
        #expect(PlaylistListItem.remote(remote).playlistDescription == "on server")
        #expect(PlaylistListItem.local(LocalPlaylist(title: "Mine")).playlistDescription == nil)
    }

    // MARK: - Transitions

    @Test("Transition ids match the destination's")
    func transitionIDsMatchDestination() {
        let localPlaylist = LocalPlaylist(title: "Mine")
        let remote = Self.remotePlaylist()

        #expect(
            PlaylistListItem.local(localPlaylist).transitionID
                == PlaylistSource.local(localPlaylist.id).transitionID
        )
        #expect(
            PlaylistListItem.remote(remote).transitionID
                == PlaylistSource.remote(remote.id, instance: nil).transitionID
        )
    }

    @Test("Transition id is not the row identity")
    func transitionIDIsSeparateFromIdentity() {
        let playlist = Self.remotePlaylist()
        let item = PlaylistListItem.remote(playlist)

        #expect(item.transitionID != AnyHashable(item.id))
    }

    // MARK: - Search

    @Test("An empty query keeps everything, in order")
    func emptyQueryKeepsOrder() {
        let items = [
            PlaylistListItem.remote(Self.remotePlaylist(id: "A", title: "Zebra")),
            PlaylistListItem.remote(Self.remotePlaylist(id: "B", title: "Apple"))
        ]

        let filtered = PlaylistListItem.filtered(items, searchText: "")

        #expect(filtered.map(\.title) == ["Zebra", "Apple"])
    }

    @Test("Titles match case-insensitively")
    func matchesTitleIgnoringCase() {
        let items = [
            PlaylistListItem.remote(Self.remotePlaylist(id: "A", title: "Watch Later")),
            PlaylistListItem.remote(Self.remotePlaylist(id: "B", title: "Music"))
        ]

        #expect(PlaylistListItem.filtered(items, searchText: "watch").map(\.title) == ["Watch Later"])
        #expect(PlaylistListItem.filtered(items, searchText: "MUS").map(\.title) == ["Music"])
    }

    @Test("Descriptions match too, on both sides")
    func matchesDescription() {
        let items = [
            PlaylistListItem.local(LocalPlaylist(title: "Mine", description: "cooking videos")),
            PlaylistListItem.remote(Self.remotePlaylist(id: "A", title: "Theirs", description: "guitar lessons"))
        ]

        #expect(PlaylistListItem.filtered(items, searchText: "cooking").map(\.title) == ["Mine"])
        #expect(PlaylistListItem.filtered(items, searchText: "guitar").map(\.title) == ["Theirs"])
    }

    @Test("A query nothing matches leaves nothing")
    func matchesNothing() {
        let items = [PlaylistListItem.remote(Self.remotePlaylist(title: "Music"))]

        #expect(PlaylistListItem.filtered(items, searchText: "podcast").isEmpty)
    }

    @Test("A playlist without a description is not a match by absence")
    func missingDescriptionDoesNotMatch() {
        let items = [PlaylistListItem.local(LocalPlaylist(title: "Mine"))]

        #expect(PlaylistListItem.filtered(items, searchText: "anything").isEmpty)
    }
}
