//
//  PipedResponseTests.swift
//  YatteeTests
//
//  Piped answers with two things the app used to take at face value: `-1`
//  standing in for a number it does not have, and an error body served under
//  HTTP 200. Both have to be read as what they are before they reach a row or
//  a toast.
//

import Testing
import Foundation
@testable import Yattee

// MARK: - Helpers

private let pipedBaseURL = URL(string: "https://piped.example.com")!

/// Builds one stream row of a Piped playlist page, with whatever the server
/// claims for the two sentinel-carrying fields.
private func pipedStreamJSON(
    videoId: String,
    title: String,
    views: Int64?,
    uploaded: Int64?
) -> String {
    var fields: [String] = [
        "\"url\": \"/watch?v=\(videoId)\"",
        "\"title\": \"\(title)\"",
        "\"uploaderName\": \"Test Channel\"",
        "\"uploaderUrl\": \"/channel/UCtest\"",
        "\"duration\": 120",
        "\"thumbnail\": \"https://piped.example.com/thumb.jpg\""
    ]
    if let views {
        fields.append("\"views\": \(views)")
    }
    if let uploaded {
        fields.append("\"uploaded\": \(uploaded)")
    }
    return "{\(fields.joined(separator: ", "))}"
}

/// Builds the first page of `/playlists/{id}`. `videos` defaults to the number
/// of rows the page carries, which is what a healthy server sends.
private func pipedPlaylistPageJSON(streams: [String], videos: Int64? = nil) -> Data {
    Data("""
    {
        "name": "Watch Later",
        "uploader": "arek",
        "uploaderUrl": "/channel/UCowner",
        "videos": \(videos ?? Int64(streams.count)),
        "relatedStreams": [\(streams.joined(separator: ",\n"))],
        "nextpage": null
    }
    """.utf8)
}

// MARK: - Sentinels

@Suite("Piped Sentinel Values")
struct PipedSentinelTests {

    @Test("A negative count is no count at all")
    func negativeCountIsNil() {
        #expect(PipedSentinel.count(-1) == nil)
        #expect(PipedSentinel.count(-999) == nil)
    }

    @Test("A count the server has is carried through, zero included")
    func realCountsSurvive() {
        #expect(PipedSentinel.count(0) == 0)
        #expect(PipedSentinel.count(1_234_567) == 1_234_567)
    }

    @Test("A missing count stays missing")
    func absentCountIsNil() {
        #expect(PipedSentinel.count(nil) == nil)
    }

    @Test("A negative upload timestamp is not a date in 1969")
    func negativeUploadedIsNil() {
        #expect(PipedSentinel.uploadedDate(-1) == nil)
    }

    @Test("An upload timestamp is read as epoch milliseconds")
    func uploadedIsMilliseconds() {
        // 2021-01-01T00:00:00Z in milliseconds.
        let date = PipedSentinel.uploadedDate(1_609_459_200_000)
        #expect(date == Date(timeIntervalSince1970: 1_609_459_200))
    }

    @Test("A missing upload timestamp stays missing")
    func absentUploadedIsNil() {
        #expect(PipedSentinel.uploadedDate(nil) == nil)
    }

    @Test("A playlist row of sentinels comes back with neither views nor a date")
    func playlistRowSentinelsAreDropped() throws {
        let page = pipedPlaylistPageJSON(streams: [
            pipedStreamJSON(videoId: "aaa", title: "Sentinels", views: -1, uploaded: -1)
        ])

        let snapshot = try PipedAPI.userPlaylistSnapshot(
            fromPageJSON: [page],
            playlistID: "playlist-uuid",
            instanceURL: pipedBaseURL
        )

        let video = try #require(snapshot.entries.first?.video)
        #expect(video.viewCount == nil)
        #expect(video.publishedAt == nil)
    }

    @Test("A playlist row with real numbers keeps them, milliseconds and all")
    func playlistRowRealValuesSurvive() throws {
        let page = pipedPlaylistPageJSON(streams: [
            pipedStreamJSON(videoId: "bbb", title: "Real", views: 4200, uploaded: 1_609_459_200_000)
        ])

        let snapshot = try PipedAPI.userPlaylistSnapshot(
            fromPageJSON: [page],
            playlistID: "playlist-uuid",
            instanceURL: pipedBaseURL
        )

        let video = try #require(snapshot.entries.first?.video)
        #expect(video.viewCount == 4200)
        #expect(video.publishedAt == Date(timeIntervalSince1970: 1_609_459_200))
    }

    @Test("A playlist that says it holds -1 videos is counted by its rows")
    func playlistCountSentinelFallsBackToTheRows() throws {
        let page = pipedPlaylistPageJSON(
            streams: [
                pipedStreamJSON(videoId: "aaa", title: "First", views: 10, uploaded: nil),
                pipedStreamJSON(videoId: "bbb", title: "Second", views: 20, uploaded: nil)
            ],
            videos: -1
        )

        let snapshot = try PipedAPI.userPlaylistSnapshot(
            fromPageJSON: [page],
            playlistID: "playlist-uuid",
            instanceURL: pipedBaseURL
        )

        // "-1 videos" would show as a row count in the list, and reads as a
        // playlist that lost everything in it.
        #expect(snapshot.playlist.videoCount == 2)
    }

    @Test("A playlist count the server has beats the row count")
    func playlistCountIsTakenFromTheServer() throws {
        // More than the page carries — the rest is behind the pager.
        let page = pipedPlaylistPageJSON(
            streams: [pipedStreamJSON(videoId: "aaa", title: "First", views: 10, uploaded: nil)],
            videos: 42
        )

        let snapshot = try PipedAPI.userPlaylistSnapshot(
            fromPageJSON: [page],
            playlistID: "playlist-uuid",
            instanceURL: pipedBaseURL
        )

        #expect(snapshot.playlist.videoCount == 42)
    }
}

// MARK: - Write Responses

@Suite("Piped Write Response Decoding")
struct PipedWriteResponseTests {

    /// Stands in for the create-playlist success shape, which is declared where
    /// only that one call can see it.
    private struct CreateShape: Decodable {
        let playlistId: String
    }

    @Test("An error body under HTTP 200 is an error, not a message")
    func errorBodyBecomesServerError() throws {
        let data = Data(#"{"error":"Video not found"}"#.utf8)

        #expect(throws: APIError.serverError("Video not found")) {
            _ = try PipedAPI.decodeWriteResponse(PipedMessageResponse.self, from: data)
        }
    }

    @Test("The server's own words reach the toast")
    func errorMessageIsReadable() {
        let data = Data(#"{"error":"Index out of bounds"}"#.utf8)

        do {
            _ = try PipedAPI.decodeWriteResponse(PipedMessageResponse.self, from: data)
            Issue.record("An error body decoded as a success")
        } catch {
            #expect(error.localizedDescription.contains("Index out of bounds"))
        }
    }

    @Test("A success body still decodes")
    func successBodyDecodes() throws {
        let data = Data(#"{"message":"ok"}"#.utf8)

        let response = try PipedAPI.decodeWriteResponse(PipedMessageResponse.self, from: data)
        #expect(response.message == "ok")
    }

    @Test("An error alongside a message is still an error")
    func errorWinsOverMessage() throws {
        let data = Data(#"{"error":"Video not found","message":"ok"}"#.utf8)

        #expect(throws: APIError.serverError("Video not found")) {
            _ = try PipedAPI.decodeWriteResponse(PipedMessageResponse.self, from: data)
        }
    }

    @Test("A blank error is not treated as a failure")
    func blankErrorFallsThroughToTheSuccessShape() throws {
        let data = Data(#"{"error":"  ","message":"ok"}"#.utf8)

        let response = try PipedAPI.decodeWriteResponse(PipedMessageResponse.self, from: data)
        #expect(response.message == "ok")
    }

    @Test("The same check guards every write shape, not just the message one")
    func createShapeIsGuardedToo() throws {
        let failure = Data(#"{"error":"You are not authorized"}"#.utf8)
        #expect(throws: APIError.serverError("You are not authorized")) {
            _ = try PipedAPI.decodeWriteResponse(CreateShape.self, from: failure)
        }

        let success = Data(#"{"playlistId":"abc-123"}"#.utf8)
        let response = try PipedAPI.decodeWriteResponse(CreateShape.self, from: success)
        #expect(response.playlistId == "abc-123")
    }

    @Test("A body that is neither shape is still a decoding failure")
    func unknownBodyIsADecodingError() {
        let data = Data(#"{"unexpected":true}"#.utf8)

        do {
            _ = try PipedAPI.decodeWriteResponse(PipedMessageResponse.self, from: data)
            Issue.record("An unknown body decoded as a success")
        } catch let error as APIError {
            guard case .decodingError = error else {
                Issue.record("Expected a decoding error, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected an APIError, got \(error)")
        }
    }
}
