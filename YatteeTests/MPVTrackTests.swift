//
//  MPVTrackTests.swift
//  YatteeTests
//
//  Tests for decoding mpv's track-list property into MPVTrack.
//

import Testing
import Foundation
@testable import Yattee

@Suite("MPVTrack Decoding Tests")
struct MPVTrackDecodingTests {
    /// Realistic mpv track-list JSON for an MKV with two audio tracks,
    /// one embedded subtitle, and one external (sub-add) subtitle.
    static let fixture = """
    [
        {"id":1,"type":"video","src-id":0,"albumart":false,"default":true,"forced":false,
         "dependent":false,"visual-impaired":false,"hearing-impaired":false,"external":false,
         "selected":true,"main-selection":0,"ff-index":0,"decoder-desc":"hevc","codec":"hevc",
         "demux-w":3840,"demux-h":1600,"demux-fps":23.976},
        {"id":1,"type":"audio","src-id":1,"title":"Surround 7.1","lang":"eng","audio-channels":8,
         "albumart":false,"default":true,"forced":false,"external":false,"selected":true,
         "codec":"truehd","demux-channel-count":8,"demux-samplerate":48000},
        {"id":2,"type":"audio","src-id":2,"lang":"pol","albumart":false,"default":false,
         "forced":false,"external":false,"selected":false,"codec":"eac3",
         "demux-channel-count":6,"demux-samplerate":48000},
        {"id":1,"type":"sub","src-id":3,"lang":"eng","albumart":false,"default":false,
         "forced":true,"external":false,"selected":false,"codec":"subrip"},
        {"id":2,"type":"sub","title":"english.srt","lang":"en","default":false,"forced":false,
         "external":true,"external-filename":"/tmp/english.srt","selected":false,"codec":"subrip"}
    ]
    """

    @Test("Decodes full track-list fixture")
    func decodesFixture() {
        let tracks = MPVClient.parseTrackList(json: Self.fixture)
        #expect(tracks.count == 5)

        let video = tracks[0]
        #expect(video.type == .video)
        #expect(video.trackID == 1)
        #expect(video.isDefault)
        #expect(video.isSelected)
        #expect(video.width == 3840)
        #expect(video.height == 1600)
        #expect(video.fps == 23.976)

        let mainAudio = tracks[1]
        #expect(mainAudio.type == .audio)
        #expect(mainAudio.title == "Surround 7.1")
        #expect(mainAudio.lang == "eng")
        #expect(mainAudio.channelCount == 8)
        #expect(mainAudio.sampleRate == 48000)
        #expect(mainAudio.isSelected)
        #expect(!mainAudio.isExternal)

        let secondAudio = tracks[2]
        #expect(secondAudio.trackID == 2)
        #expect(secondAudio.lang == "pol")
        #expect(!secondAudio.isSelected)

        let forcedSub = tracks[3]
        #expect(forcedSub.type == .sub)
        #expect(forcedSub.isForced)
        #expect(!forcedSub.isExternal)

        let externalSub = tracks[4]
        #expect(externalSub.isExternal)
    }

    @Test("IDs are unique across types even when mpv ids collide")
    func uniqueIDs() {
        let tracks = MPVClient.parseTrackList(json: Self.fixture)
        let ids = Set(tracks.map(\.id))
        #expect(ids.count == tracks.count)
    }

    @Test("Minimal entry decodes with defaults")
    func minimalEntry() {
        let tracks = MPVClient.parseTrackList(json: #"[{"id":3,"type":"audio"}]"#)
        #expect(tracks.count == 1)
        let track = tracks[0]
        #expect(track.trackID == 3)
        #expect(!track.isDefault)
        #expect(!track.isForced)
        #expect(!track.isExternal)
        #expect(!track.isSelected)
        #expect(track.lang == nil)
        #expect(track.codec == nil)
    }

    @Test("One bad entry is dropped, the rest survive")
    func lenientDecoding() {
        let json = #"[{"id":1,"type":"audio"},{"id":"broken","type":"audio"},{"id":2,"type":"sub"}]"#
        let tracks = MPVClient.parseTrackList(json: json)
        #expect(tracks.count == 2)
        #expect(tracks[0].trackID == 1)
        #expect(tracks[1].type == .sub)
    }

    @Test("Unknown track type drops only that entry")
    func unknownType() {
        let json = #"[{"id":1,"type":"attachment"},{"id":1,"type":"audio"}]"#
        let tracks = MPVClient.parseTrackList(json: json)
        #expect(tracks.count == 1)
        #expect(tracks[0].type == .audio)
    }

    @Test("Garbage input yields empty list")
    func garbageInput() {
        #expect(MPVClient.parseTrackList(json: "not json").isEmpty)
        #expect(MPVClient.parseTrackList(json: "").isEmpty)
        #expect(MPVClient.parseTrackList(json: "{}").isEmpty)
    }
}

@Suite("MPVTrack Language Matching Tests")
struct MPVTrackLanguageTests {
    private func track(lang: String?, title: String? = nil) -> MPVTrack {
        MPVTrack(trackID: 1, type: .audio, title: title, lang: lang)
    }

    @Test("Normalizes ISO 639-2 codes to two-letter form")
    func normalization() {
        #expect(track(lang: "eng").baseLanguageCode == "en")
        #expect(track(lang: "pol").baseLanguageCode == "pl")
        #expect(track(lang: "en").baseLanguageCode == "en")
        #expect(track(lang: "en-US").baseLanguageCode == "en")
        #expect(track(lang: "und").baseLanguageCode == nil)
        #expect(track(lang: nil).baseLanguageCode == nil)
    }

    @Test("Matches user preference codes against Matroska codes")
    func preferenceMatching() {
        #expect(track(lang: "eng").matchesLanguage("en"))
        #expect(track(lang: "en").matchesLanguage("eng"))
        #expect(track(lang: "pol").matchesLanguage("pl"))
        #expect(!track(lang: "eng").matchesLanguage("pl"))
        #expect(!track(lang: nil).matchesLanguage("en"))
        #expect(!track(lang: "eng").matchesLanguage(nil))
        #expect(!track(lang: "eng").matchesLanguage(""))
    }

    @Test("Display name prefers title, falls back to language")
    func displayName() {
        #expect(track(lang: "eng", title: "Commentary").displayName == "Commentary")
        // Localized language name for "en" under the current test locale
        let name = track(lang: "eng").displayName
        #expect(!name.isEmpty)
        #expect(name != "eng")
    }
}
