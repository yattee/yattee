//
//  DirectMediaProbeTests.swift
//  YatteeTests
//

import Testing
import Foundation
@testable import Yattee

@Suite("DirectMediaProbe Tests")
struct DirectMediaProbeTests {
    private typealias Headers = DirectMediaProbe.ResponseHeaders

    @Test("video/* Content-Type is media, filename comes from Content-Disposition")
    func videoContentType() {
        let headers = Headers(
            contentType: "video/x-matroska",
            contentDisposition: "attachment; filename=\"Ted Lasso S04E05 1080p.mkv\"",
            contentLength: 3_847_537_440
        )
        let expected = DirectMediaProbeResult(
            filename: "Ted Lasso S04E05 1080p.mkv",
            mimeType: "video/x-matroska",
            contentLength: 3_847_537_440
        )
        #expect(DirectMediaProbe.classify(headers) == .media(expected))
    }

    @Test("text/html is not media")
    func htmlIsNotMedia() {
        #expect(DirectMediaProbe.classify(Headers(contentType: "text/html; charset=utf-8")) == .notMedia)
    }

    @Test("octet-stream without filename needs a sniff")
    func octetStreamUnknown() {
        #expect(DirectMediaProbe.classify(Headers(contentType: "application/octet-stream")) == .unknown)
        #expect(DirectMediaProbe.classify(Headers(contentType: nil)) == .unknown)
        #expect(DirectMediaProbe.classify(Headers(statusCode: 405)) == .unknown)
    }

    @Test("octet-stream with a media filename is media")
    func octetStreamWithFilename() {
        let headers = Headers(
            contentType: "application/octet-stream",
            contentDisposition: "attachment; filename*=UTF-8''Episode%2001.mp4"
        )
        guard case .media(let result) = DirectMediaProbe.classify(headers) else {
            Issue.record("Expected media"); return
        }
        #expect(result.filename == "Episode 01.mp4")
        #expect(result.mimeType == "video/mp4")
    }

    @Test("HLS manifest types are media")
    func hlsTypes() {
        #expect(DirectMediaProbe.isPlayableMediaType("application/vnd.apple.mpegurl"))
        #expect(DirectMediaProbe.isPlayableMediaType("application/dash+xml"))
        #expect(!DirectMediaProbe.isPlayableMediaType("application/json"))
    }

    @Test("Content-Disposition parsing prefers filename* and strips paths")
    func contentDisposition() {
        #expect(DirectMediaProbe.filename(fromContentDisposition: "inline; filename=\"a.mkv\"; filename*=UTF-8''b%20c.mkv") == "b c.mkv")
        #expect(DirectMediaProbe.filename(fromContentDisposition: "attachment; filename=../../evil.mp4") == "evil.mp4")
        #expect(DirectMediaProbe.filename(fromContentDisposition: "attachment") == nil)
        #expect(DirectMediaProbe.filename(fromContentDisposition: nil) == nil)
    }

    @Test("Content-Range total wins over Content-Length")
    func contentRangeTotal() {
        let headers = Headers(statusCode: 206, contentLength: 64, contentRange: "bytes 0-63/1000")
        #expect(headers.totalLength == 1000)
    }

    @Test("Magic bytes identify containers")
    func magicBytes() {
        let mkv = Data([0x1A, 0x45, 0xDF, 0xA3, 0xA3, 0x42, 0x86, 0x81]) + Data("matroska".utf8)
        #expect(DirectMediaProbe.sniffMimeType(mkv) == "video/x-matroska")
        let webm = Data([0x1A, 0x45, 0xDF, 0xA3, 0x9F, 0x42, 0x86, 0x81, 0x01, 0x42, 0x82, 0x84]) + Data("webm".utf8)
        #expect(DirectMediaProbe.sniffMimeType(webm) == "video/webm")
        let mp4 = Data([0, 0, 0, 0x18]) + Data("ftypisom".utf8) + Data(repeating: 0, count: 8)
        #expect(DirectMediaProbe.sniffMimeType(mp4) == "video/mp4")
        let m4a = Data([0, 0, 0, 0x18]) + Data("ftypM4A ".utf8)
        #expect(DirectMediaProbe.sniffMimeType(m4a) == "audio/mp4")
        #expect(DirectMediaProbe.sniffMimeType(Data("ID3\u{03}".utf8)) == "audio/mpeg")
        #expect(DirectMediaProbe.sniffMimeType(Data("fLaC".utf8)) == "audio/flac")
        #expect(DirectMediaProbe.sniffMimeType(Data("RIFF....AVI ".utf8)) == "video/x-msvideo")
        #expect(DirectMediaProbe.sniffMimeType(Data("#EXTM3U\n#EXT-X-VERSION:3".utf8)) == "application/vnd.apple.mpegurl")
        var ts = Data(repeating: 0, count: 200); ts[0] = 0x47; ts[188] = 0x47
        #expect(DirectMediaProbe.sniffMimeType(ts) == "video/mp2t")
        #expect(DirectMediaProbe.sniffMimeType(Data("<!DOCTYPE html><html>".utf8)) == nil)
        #expect(DirectMediaProbe.sniffMimeType(Data("{\"a\":1}".utf8)) == nil)
    }

    @Test("Probe result drives Video title and Stream metadata for opaque URLs")
    func helperUsesProbe() {
        let url = URL(string: "https://store-073.wnam.tb-cdn.io/dld/854b43c0-41bb?token=abc")!
        let probe = DirectMediaProbeResult(filename: "Show S01E01.mkv", mimeType: "video/x-matroska", contentLength: 42)
        let video = DirectMediaHelper.createVideo(from: url, probe: probe)
        #expect(video.title == "Show S01E01")
        #expect(!video.isLive)
        let stream = DirectMediaHelper.createStream(from: url, probe: probe)
        #expect(stream.format == "mkv")
        #expect(stream.mimeType == "video/x-matroska")
        #expect(stream.fileSize == 42)
        #expect(!stream.isAudioOnly)

        let audio = DirectMediaHelper.createStream(from: url, probe: DirectMediaProbeResult(filename: nil, mimeType: "audio/flac", contentLength: nil))
        #expect(audio.isAudioOnly)
        let hls = DirectMediaHelper.createVideo(from: url, probe: DirectMediaProbeResult(filename: nil, mimeType: "application/vnd.apple.mpegurl", contentLength: nil))
        #expect(hls.isLive)
    }

    @Test("Without a probe the path extension still rules")
    func helperWithoutProbe() {
        let url = URL(string: "https://example.com/clip.mp4")!
        #expect(DirectMediaHelper.createVideo(from: url).title == "clip")
        #expect(DirectMediaHelper.createStream(from: url).format == "mp4")
    }
}
