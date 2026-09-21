//
//  DirectMediaProbe.swift
//  Yattee
//
//  Decides whether an arbitrary http(s) URL serves a media file mpv can play
//  as-is, so the app can skip Yattee Server extraction for debrid/CDN download
//  links whose path is an opaque ID (TorBox, Real-Debrid, presigned S3, …).
//

import Foundation

/// What the probe learned about a URL that serves playable media.
struct DirectMediaProbeResult: Sendable, Equatable {
    /// Filename reported by the server (Content-Disposition), if any.
    let filename: String?
    /// Media type the server reported, or the one sniffed from the payload.
    let mimeType: String?
    /// Content-Length, if the server sent one.
    let contentLength: Int64?
}

enum DirectMediaProbe {
    /// How long a probe may take before falling back to extraction.
    static let timeout: TimeInterval = 10
    /// How many leading bytes to sniff when the server's type is generic.
    static let sniffLength = 512

    // MARK: - Network

    /// Asks the server what it serves at `url` and returns a result when it is
    /// something mpv can play directly. `nil` means "not obviously media",
    /// e.g. an HTML page, and the caller should try Yattee Server instead.
    static func probe(_ url: URL, session: URLSession = .shared) async -> DirectMediaProbeResult? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }

        var headResult: HeaderVerdict?
        if let response = await head(url, session: session) {
            headResult = classify(response)
            switch headResult {
            case .media(let result):
                LoggingService.shared.debug(
                    "[DirectMediaProbe] HEAD says media: \(result.mimeType ?? "-") \(result.filename ?? "")",
                    category: .player
                )
                return result
            case .notMedia:
                LoggingService.shared.debug("[DirectMediaProbe] HEAD says not media for \(url.host ?? "")", category: .player)
                return nil
            case .unknown, .none:
                break
            }
        }

        // HEAD failed or the type was generic: look at the first bytes.
        guard let sniffed = await sniff(url, session: session) else {
            return nil
        }
        let headers = sniffed.headers
        guard let mimeType = sniffMimeType(sniffed.data) ?? mediaTypeFromFilename(headers) else {
            LoggingService.shared.debug("[DirectMediaProbe] payload not recognised for \(url.host ?? "")", category: .player)
            return nil
        }
        LoggingService.shared.debug("[DirectMediaProbe] sniffed \(mimeType) for \(url.host ?? "")", category: .player)
        return DirectMediaProbeResult(
            filename: headers.filename,
            mimeType: mimeType,
            contentLength: headers.totalLength
        )
    }

    private static func head(_ url: URL, session: URLSession) async -> HTTPURLResponse? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "HEAD"
        applyUserAgent(&request)
        do {
            let (_, response) = try await session.data(for: request)
            return response as? HTTPURLResponse
        } catch {
            LoggingService.shared.debug("[DirectMediaProbe] HEAD failed: \(error.localizedDescription)", category: .player)
            return nil
        }
    }

    private static func sniff(_ url: URL, session: URLSession) async -> (headers: ResponseHeaders, data: Data)? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("bytes=0-\(sniffLength - 1)", forHTTPHeaderField: "Range")
        applyUserAgent(&request)
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            var data = Data()
            data.reserveCapacity(sniffLength)
            for try await byte in bytes {
                data.append(byte)
                if data.count >= sniffLength { break }
            }
            return (ResponseHeaders(http), data)
        } catch {
            LoggingService.shared.debug("[DirectMediaProbe] sniff failed: \(error.localizedDescription)", category: .player)
            return nil
        }
    }

    private static func applyUserAgent(_ request: inout URLRequest) {
        let settings = UserAgentConfiguration.shared.current()
        if let userAgent = settings.userAgent, !userAgent.isEmpty {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
    }

    // MARK: - Header classification

    enum HeaderVerdict: Equatable {
        case media(DirectMediaProbeResult)
        case notMedia
        /// Generic type (octet-stream, missing) — needs a payload sniff.
        case unknown
    }

    /// The headers that matter, pulled out of an `HTTPURLResponse`.
    struct ResponseHeaders {
        let statusCode: Int
        let contentType: String?
        let contentDisposition: String?
        let contentLength: Int64?
        let contentRange: String?

        init(_ response: HTTPURLResponse) {
            statusCode = response.statusCode
            contentType = response.value(forHTTPHeaderField: "Content-Type")
            contentDisposition = response.value(forHTTPHeaderField: "Content-Disposition")
            contentLength = response.value(forHTTPHeaderField: "Content-Length").flatMap { Int64($0) }
            contentRange = response.value(forHTTPHeaderField: "Content-Range")
        }

        init(statusCode: Int = 200, contentType: String? = nil, contentDisposition: String? = nil,
             contentLength: Int64? = nil, contentRange: String? = nil) {
            self.statusCode = statusCode
            self.contentType = contentType
            self.contentDisposition = contentDisposition
            self.contentLength = contentLength
            self.contentRange = contentRange
        }

        /// Filename from Content-Disposition (`filename*=` wins over `filename=`).
        var filename: String? {
            DirectMediaProbe.filename(fromContentDisposition: contentDisposition)
        }

        /// The full size: Content-Range's total for a 206, else Content-Length.
        var totalLength: Int64? {
            if let contentRange,
               let slash = contentRange.lastIndex(of: "/"),
               let total = Int64(contentRange[contentRange.index(after: slash)...].trimmingCharacters(in: .whitespaces)) {
                return total
            }
            return contentLength
        }

        /// The media type without parameters, lowercased.
        var essenceType: String? {
            guard let contentType else { return nil }
            let essence = contentType.split(separator: ";", maxSplits: 1).first.map(String.init) ?? contentType
            let trimmed = essence.trimmingCharacters(in: .whitespaces).lowercased()
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    static func classify(_ response: HTTPURLResponse) -> HeaderVerdict {
        classify(ResponseHeaders(response))
    }

    static func classify(_ headers: ResponseHeaders) -> HeaderVerdict {
        guard (200...299).contains(headers.statusCode) else {
            // 403/405 on HEAD is common for CDNs that only serve GET; let the sniff decide.
            return .unknown
        }

        let type = headers.essenceType
        let filename = headers.filename

        if let type, isPlayableMediaType(type) {
            return .media(DirectMediaProbeResult(filename: filename, mimeType: type, contentLength: headers.totalLength))
        }

        // A generic type with a media filename attached is still a media file.
        if let fromName = mediaTypeFromFilename(headers), type.map(isGenericType) ?? true {
            return .media(DirectMediaProbeResult(filename: filename, mimeType: fromName, contentLength: headers.totalLength))
        }

        guard let type else { return .unknown }
        if isGenericType(type) { return .unknown }
        return .notMedia
    }

    /// Types mpv plays straight from the network.
    static func isPlayableMediaType(_ type: String) -> Bool {
        if type.hasPrefix("video/") || type.hasPrefix("audio/") { return true }
        return [
            "application/vnd.apple.mpegurl",
            "application/x-mpegurl",
            "application/dash+xml",
            "application/mp4",
            "application/x-matroska",
            "application/ogg",
            "application/x-flac",
            "application/mpeg",
            "application/vnd.rn-realmedia",
        ].contains(type)
    }

    /// Types that say nothing about the payload.
    static func isGenericType(_ type: String) -> Bool {
        [
            "application/octet-stream",
            "application/x-download",
            "application/force-download",
            "application/download",
            "binary/octet-stream",
            "application/unknown",
        ].contains(type)
    }

    /// A media type derived from the Content-Disposition filename's extension.
    static func mediaTypeFromFilename(_ headers: ResponseHeaders) -> String? {
        guard let filename = headers.filename else { return nil }
        let ext = (filename as NSString).pathExtension.lowercased()
        guard DirectMediaHelper.allExtensions.contains(ext) else { return nil }
        return DirectMediaHelper.mimeType(for: ext) ?? "video/\(ext)"
    }

    /// Parses `filename*=UTF-8''…` or `filename="…"` out of a Content-Disposition value.
    static func filename(fromContentDisposition value: String?) -> String? {
        guard let value else { return nil }
        var plain: String?
        for part in value.split(separator: ";").dropFirst() {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            var raw = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if key == "filename*" {
                // RFC 5987: charset'lang'percent-encoded
                if let lastQuote = raw.lastIndex(of: "'") {
                    raw = String(raw[raw.index(after: lastQuote)...])
                }
                raw = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if let decoded = raw.removingPercentEncoding, !decoded.isEmpty {
                    return (decoded as NSString).lastPathComponent
                }
            } else if key == "filename" {
                raw = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if !raw.isEmpty { plain = (raw as NSString).lastPathComponent }
            }
        }
        return plain
    }

    // MARK: - Payload sniffing

    /// Recognises common container signatures in the first bytes of a file.
    static func sniffMimeType(_ data: Data) -> String? {
        guard data.count >= 4 else { return nil }
        let bytes = [UInt8](data.prefix(sniffLength))

        func starts(with signature: [UInt8], at offset: Int = 0) -> Bool {
            guard bytes.count >= offset + signature.count else { return false }
            return Array(bytes[offset..<offset + signature.count]) == signature
        }
        func ascii(_ s: String) -> [UInt8] { Array(s.utf8) }

        // EBML: Matroska or WebM. The DocType string follows within the header.
        if starts(with: [0x1A, 0x45, 0xDF, 0xA3]) {
            if let text = String(bytes: bytes.prefix(64), encoding: .isoLatin1), text.contains("webm") {
                return "video/webm"
            }
            return "video/x-matroska"
        }
        // ISO BMFF: mp4/mov/m4a/3gp — "ftyp" at offset 4.
        if starts(with: ascii("ftyp"), at: 4) {
            let brand = String(bytes: bytes[8..<min(12, bytes.count)], encoding: .isoLatin1) ?? ""
            if brand.hasPrefix("M4A") { return "audio/mp4" }
            if brand.hasPrefix("qt") { return "video/quicktime" }
            if brand.hasPrefix("3g") { return "video/3gpp" }
            return "video/mp4"
        }
        if starts(with: ascii("OggS")) { return "application/ogg" }
        if starts(with: ascii("fLaC")) { return "audio/flac" }
        if starts(with: ascii("ID3")) { return "audio/mpeg" }
        if bytes[0] == 0xFF, bytes[1] & 0xE6 == 0xE2 || bytes[1] & 0xF6 == 0xF2 { return "audio/mpeg" } // MPEG audio frame sync
        if starts(with: ascii("RIFF")) {
            if starts(with: ascii("AVI "), at: 8) { return "video/x-msvideo" }
            if starts(with: ascii("WAVE"), at: 8) { return "audio/wav" }
            return nil
        }
        if starts(with: ascii("FLV")) { return "video/x-flv" }
        if starts(with: [0x30, 0x26, 0xB2, 0x75]) { return "video/x-ms-wmv" } // ASF
        if starts(with: [0x00, 0x00, 0x01, 0xBA]) { return "video/mpeg" } // MPEG-PS
        if starts(with: [0x00, 0x00, 0x01, 0xB3]) { return "video/mpeg" } // MPEG-1/2 video ES
        if starts(with: ascii(".RMF")) { return "application/vnd.rn-realmedia" }
        // MPEG-TS: sync byte 0x47 repeating every 188 bytes.
        if bytes[0] == 0x47, bytes.count > 188, bytes[188] == 0x47 { return "video/mp2t" }

        // Text-based manifests.
        if let text = String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .isoLatin1) {
            let head = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if head.hasPrefix("#EXTM3U") { return "application/vnd.apple.mpegurl" }
            if head.hasPrefix("<") && head.contains("<MPD") { return "application/dash+xml" }
        }
        return nil
    }
}
