//
//  QualitySelectorView+StreamHelpers.swift
//  Yattee
//
//  Stream filtering, sorting, and helper methods for QualitySelectorView.
//

import SwiftUI

extension QualitySelectorView {
    // MARK: - Stream Categories

    /// Adaptive streams (HLS, DASH) - auto quality selection.
    /// Deduplicated by URL to avoid showing identical entries.
    var adaptiveStreams: [Stream] {
        let adaptive = streams.filter { (stream: Stream) -> Bool in
            let format = StreamFormat.detect(from: stream)
            return format == .hls || format == .dash
        }

        // Deduplicate by URL - keep first occurrence
        var seenURLs: Set<URL> = []
        return adaptive.filter { stream in
            if seenURLs.contains(stream.url) {
                return false
            }
            seenURLs.insert(stream.url)
            return true
        }
    }

    /// Video streams (both muxed and video-only), sorted with preferred quality first.
    /// When showAdvancedStreamDetails is false, filters to best stream per resolution.
    /// Downloaded streams (local files) are always included and shown first.
    var videoStreams: [Stream] {
        let maxRes: StreamResolution? = preferredQuality.maxResolution

        // Separate downloaded streams (always include them, shown first)
        let downloadedStreams: [Stream] = streams.filter { $0.url.isFileURL && !$0.isAudioOnly }

        // Online streams need resolution to be shown
        let onlineVideoStreams: [Stream] = streams
            .filter { (stream: Stream) -> Bool in
                !stream.url.isFileURL && !stream.isAudioOnly && stream.resolution != nil
            }
            .filter { (stream: Stream) -> Bool in
                let format = StreamFormat.detect(from: stream)
                return format != .hls && format != .dash
            }
            .sorted { (s1: Stream, s2: Stream) -> Bool in
                // Preferred quality first
                let s1Preferred: Bool = s1.resolution == maxRes
                let s2Preferred: Bool = s2.resolution == maxRes
                if s1Preferred != s2Preferred {
                    return s1Preferred
                }
                // Then by resolution (higher first)
                let res1: StreamResolution = s1.resolution ?? .p360
                let res2: StreamResolution = s2.resolution ?? .p360
                if res1 != res2 {
                    return res1 > res2
                }
                // Within same resolution, better codec ranks higher
                return videoCodecPriority(s1.videoCodec) > videoCodecPriority(s2.videoCodec)
            }

        // When advanced details are hidden, show only best stream per resolution
        if !showAdvancedStreamDetails {
            var bestByResolution: [Int: Stream] = [:]
            for stream in onlineVideoStreams {
                let height: Int = stream.resolution?.height ?? 0
                if let existing = bestByResolution[height] {
                    if videoCodecPriority(stream.videoCodec) > videoCodecPriority(existing.videoCodec) {
                        bestByResolution[height] = stream
                    }
                } else {
                    bestByResolution[height] = stream
                }
            }
            let sortedOnlineStreams: [Stream] = bestByResolution.values.sorted { (s1: Stream, s2: Stream) -> Bool in
                let s1Preferred: Bool = s1.resolution == maxRes
                let s2Preferred: Bool = s2.resolution == maxRes
                if s1Preferred != s2Preferred {
                    return s1Preferred
                }
                return (s1.resolution ?? .p360) > (s2.resolution ?? .p360)
            }
            return downloadedStreams + sortedOnlineStreams
        }

        return downloadedStreams + onlineVideoStreams
    }

    /// Recommended video streams (hardware-decodable codecs).
    var recommendedVideoStreams: [Stream] {
        videoStreams.filter { (stream: Stream) -> Bool in
            if stream.url.isFileURL { return true }
            if stream.isMuxed { return true }
            return !requiresSoftwareDecode(stream.videoCodec)
        }
    }

    /// Other video streams (software decode required).
    var otherVideoStreams: [Stream] {
        videoStreams.filter { (stream: Stream) -> Bool in
            if stream.url.isFileURL { return false }
            if stream.isMuxed { return false }
            return requiresSoftwareDecode(stream.videoCodec)
        }
    }

    /// Audio-only streams, deduplicated and sorted with preferred language first.
    var audioStreams: [Stream] {
        let allAudio: [Stream] = streams.filter { $0.isAudioOnly }

        // When advanced details are hidden, show only best stream per language
        if !showAdvancedStreamDetails {
            var bestByLanguage: [String: Stream] = [:]

            for stream in allAudio {
                let lang: String = stream.audioLanguage ?? ""
                if let existing = bestByLanguage[lang] {
                    if audioCodecPriority(stream.audioCodec) > audioCodecPriority(existing.audioCodec) {
                        bestByLanguage[lang] = stream
                    } else if audioCodecPriority(stream.audioCodec) == audioCodecPriority(existing.audioCodec) {
                        if (stream.bitrate ?? 0) > (existing.bitrate ?? 0) {
                            bestByLanguage[lang] = stream
                        }
                    }
                } else {
                    bestByLanguage[lang] = stream
                }
            }

            return bestByLanguage.values.sorted { (s1: Stream, s2: Stream) -> Bool in
                if let preferred = preferredAudioLanguage {
                    let lang1: String = s1.audioLanguage ?? ""
                    let lang2: String = s2.audioLanguage ?? ""
                    let s1Preferred: Bool = lang1.hasPrefix(preferred)
                    let s2Preferred: Bool = lang2.hasPrefix(preferred)
                    if s1Preferred != s2Preferred {
                        return s1Preferred
                    }
                } else {
                    if s1.isOriginalAudio != s2.isOriginalAudio {
                        return s1.isOriginalAudio
                    }
                }
                return (s1.audioLanguage ?? "") < (s2.audioLanguage ?? "")
            }
        }

        // Full details mode: Group by language + codec
        var bestByKey: [String: Stream] = [:]

        for stream in allAudio {
            let lang: String = stream.audioLanguage ?? ""
            let codec: String = stream.audioCodec ?? ""
            let key: String = "\(lang)|\(codec)"

            if let existing = bestByKey[key] {
                if (stream.bitrate ?? 0) > (existing.bitrate ?? 0) {
                    bestByKey[key] = stream
                }
            } else {
                bestByKey[key] = stream
            }
        }

        return bestByKey.values.sorted { (s1: Stream, s2: Stream) -> Bool in
            // Preferred language or original audio first
            if let preferred = preferredAudioLanguage {
                let lang1: String = s1.audioLanguage ?? ""
                let lang2: String = s2.audioLanguage ?? ""
                let s1Preferred: Bool = lang1.hasPrefix(preferred)
                let s2Preferred: Bool = lang2.hasPrefix(preferred)
                if s1Preferred != s2Preferred {
                    return s1Preferred
                }
            } else {
                if s1.isOriginalAudio != s2.isOriginalAudio {
                    return s1.isOriginalAudio
                }
            }

            // Then by language alphabetically
            let lang1: String = s1.audioLanguage ?? ""
            let lang2: String = s2.audioLanguage ?? ""
            if lang1 != lang2 {
                return lang1 < lang2
            }

            // Better codec ranks higher
            let codec1: Int = audioCodecPriority(s1.audioCodec)
            let codec2: Int = audioCodecPriority(s2.audioCodec)
            if codec1 != codec2 {
                return codec1 > codec2
            }

            // Higher bitrate first
            return (s1.bitrate ?? 0) > (s2.bitrate ?? 0)
        }
    }

    /// Whether we need to show audio selection (video-only streams exist).
    var hasVideoOnlyStreams: Bool {
        videoStreams.contains { $0.isVideoOnly }
    }

    /// Best audio stream for auto-selection based on preferred language setting.
    var defaultAudioStream: Stream? {
        if let preferred = preferredAudioLanguage {
            if let preferredStream = audioStreams.first(where: { ($0.audioLanguage ?? "").hasPrefix(preferred) }) {
                return preferredStream
            }
        }

        if let originalStream = audioStreams.first(where: { $0.isOriginalAudio }) {
            return originalStream
        }

        return audioStreams.first
    }

    /// Captions sorted with preferred language first.
    var sortedCaptions: [Caption] {
        captions.sorted { (c1: Caption, c2: Caption) -> Bool in
            if let preferred = preferredSubtitlesLanguage {
                let c1Preferred: Bool = c1.baseLanguageCode == preferred || c1.languageCode.hasPrefix(preferred)
                let c2Preferred: Bool = c2.baseLanguageCode == preferred || c2.languageCode.hasPrefix(preferred)
                if c1Preferred != c2Preferred {
                    return c1Preferred
                }
            }
            return c1.displayName.localizedCaseInsensitiveCompare(c2.displayName) == .orderedAscending
        }
    }

    // MARK: - Codec Helpers

    /// Returns codec priority for sorting (higher = better).
    func videoCodecPriority(_ codec: String?) -> Int {
        HardwareCapabilities.shared.codecPriority(for: codec)
    }

    /// Returns audio codec priority for sorting.
    func audioCodecPriority(_ codec: String?) -> Int {
        guard let codec = codec?.lowercased() else { return 0 }
        if codec.contains("opus") || codec.contains("aac") || codec.contains("mp4a") {
            return 1
        }
        return 0
    }

    /// Whether a codec requires software decoding.
    func requiresSoftwareDecode(_ codec: String?) -> Bool {
        HardwareCapabilities.shared.codecPriority(for: codec) == 0
    }

    // MARK: - Audio Track Parsing

    /// Parses audio track information from a stream.
    func parseAudioTrackName(_ stream: Stream) -> AudioTrackInfo {
        let isAutoDubbed: Bool = stream.audioTrackName?.contains("Auto-dubbed") == true
        let isOriginal: Bool = stream.audioTrackName?.contains("Original") == true

        let trackType: String?
        if isAutoDubbed {
            trackType = "AD"
        } else if isOriginal {
            trackType = "ORIGINAL"
        } else {
            trackType = nil
        }

        let language: String
        if let lang = stream.audioLanguage {
            let fullName: String = Locale.current.localizedString(forLanguageCode: lang) ?? lang.uppercased()
            language = shortenRegionName(fullName)
        } else if let name = stream.audioTrackName {
            let cleaned: String = name
                .replacingOccurrences(of: "(Auto-dubbed)", with: "")
                .replacingOccurrences(of: "(Original)", with: "")
                .trimmingCharacters(in: .whitespaces)
            language = shortenRegionName(cleaned)
        } else {
            language = String(localized: "stream.audio.default")
        }

        return AudioTrackInfo(language: language, trackType: trackType)
    }

    /// Shortens region names in language strings.
    private func shortenRegionName(_ name: String) -> String {
        let regionMappings: [String: String] = [
            "(United States)": "(US)",
            "(United Kingdom)": "(UK)",
            "(Germany)": "",
            "(France)": "",
            "(Spain)": "",
            "(Italy)": "",
            "(Japan)": "",
            "(China)": "",
            "(Brazil)": "",
            "(Portugal)": "",
            "(Russia)": "",
            "(Korea)": ""
        ]

        var shortened: String = name
        for (full, short) in regionMappings {
            shortened = shortened.replacingOccurrences(of: full, with: short)
        }
        return shortened.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Rate Helpers

    /// Returns the previous playback rate, or nil if at minimum.
    func previousRate() -> PlaybackRate? {
        let allRates: [PlaybackRate] = PlaybackRate.allCases
        guard let currentIndex = allRates.firstIndex(of: currentRate),
              currentIndex > 0 else {
            return nil
        }
        return allRates[currentIndex - 1]
    }

    /// Returns the next playback rate, or nil if at maximum.
    func nextRate() -> PlaybackRate? {
        let allRates: [PlaybackRate] = PlaybackRate.allCases
        guard let currentIndex = allRates.firstIndex(of: currentRate),
              currentIndex < allRates.count - 1 else {
            return nil
        }
        return allRates[currentIndex + 1]
    }

    // MARK: - Formatting Helpers

    /// Formats a file size from bytes.
    func formatFileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Formats stream details (bitrate and file size).
    func formatStreamDetails(bitrate: Int?, fileSize: String?) -> String {
        var parts: [String] = []
        if let bitrate {
            parts.append(formatBitrate(bitrate))
        }
        if let fileSize {
            parts.append(fileSize)
        }
        return parts.joined(separator: " · ")
    }

    /// Formats audio details (track type, bitrate, file size).
    func formatAudioDetails(trackType: String?, bitrate: Int?, fileSize: String?) -> String {
        var parts: [String] = []
        if let trackType {
            parts.append(trackType)
        }
        if let bitrate {
            parts.append(formatBitrate(bitrate))
        }
        if let fileSize {
            parts.append(fileSize)
        }
        return parts.joined(separator: " · ")
    }

    /// Formats a codec string for display.
    func formatCodec(_ codec: String) -> String {
        let lowercased: String = codec.lowercased()
        if lowercased.contains("avc") || lowercased.contains("h264") {
            return "H.264"
        } else if lowercased.contains("hev") || lowercased.contains("h265") || lowercased.contains("hevc") {
            return "HEVC"
        } else if lowercased.contains("vp9") || lowercased.contains("vp09") {
            return "VP9"
        } else if lowercased.contains("av1") || lowercased.contains("av01") {
            return "AV1"
        }
        return codec.uppercased()
    }

    /// Returns a color for a codec badge.
    func codecColor(_ codec: String) -> Color {
        let lowercased: String = codec.lowercased()
        if lowercased.contains("av1") || lowercased.contains("av01") {
            return .blue
        } else if lowercased.contains("vp9") || lowercased.contains("vp09") {
            return .orange
        } else if lowercased.contains("avc") || lowercased.contains("h264") {
            return .red
        } else if lowercased.contains("hev") || lowercased.contains("h265") || lowercased.contains("hevc") {
            return .green
        }
        return .gray
    }

    /// Formats a bitrate for display.
    func formatBitrate(_ bitrate: Int) -> String {
        if bitrate >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bitrate) / 1_000_000)
        } else {
            return "\(bitrate / 1000) kbps"
        }
    }
}
