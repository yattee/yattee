//
//  MPVDebugOverlay.swift
//  Yattee
//
//  Debug overlay for MPV player showing playback statistics.
//

import SwiftUI

/// Debug statistics from MPV player.
struct MPVDebugStats: Equatable {
    // Video info
    var videoCodec: String?
    var hwdecCurrent: String?
    var width: Int?
    var height: Int?
    var fps: Double?
    var estimatedVfFps: Double?

    // Audio info
    var audioCodec: String?
    var audioSampleRate: Int?
    var audioChannels: Int?

    // Playback stats
    var droppedFrameCount: Int?
    var mistimedFrameCount: Int?
    var delayedFrameCount: Int?
    var avSync: Double?
    var estimatedFrameNumber: Int?

    // Cache/Network
    var cacheDuration: Double?
    var cacheBytes: Int64?
    var demuxerCacheDuration: Double?
    var networkSpeed: Int64?

    // Container
    var fileFormat: String?
    var containerFps: Double?

    // Video Sync (tvOS-relevant for frame timing diagnostics)
    var videoSync: String?              // Current video-sync mode (e.g., "display-vdrop")
    var displayFps: Double?             // Display refresh rate MPV is targeting
    var vsyncJitter: Double?            // Vsync timing jitter in seconds
    var videoSpeedCorrection: Double?   // Speed adjustment for display sync (1.0 = no adjustment)
    var audioSpeedCorrection: Double?   // Audio speed adjustment
    var framedrop: String?              // Frame drop mode (decoder, vo, decoder+vo)
    var displayLinkFps: Double?         // CADisplayLink preferred frame rate
}

/// Debug overlay view for MPV player.
struct MPVDebugOverlay: View {
    let stats: MPVDebugStats
    @Binding var isVisible: Bool
    var isLandscape: Bool = false
    /// Callback for tvOS close button (tvOS can't tap outside to dismiss)
    var onClose: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    #if os(tvOS)
    @FocusState private var isCloseButtonFocused: Bool
    #endif

    // Font sizes - platform-specific (tvOS needs larger sizes for TV viewing distance)
    #if os(tvOS)
    private var headerSize: CGFloat { 32 }
    private var sectionSize: CGFloat { 26 }
    private var rowSize: CGFloat { 24 }
    private var closeButtonSize: CGFloat { 28 }
    private var columnSpacing: CGFloat { 40 }
    private var columnMinWidth: CGFloat { 280 }
    private var maxOverlayWidth: CGFloat { 1450 }  // Extra width for Frame Sync column
    private var padding: CGFloat { 32 }
    private var cornerRadius: CGFloat { 20 }
    #else
    private var headerSize: CGFloat { isLandscape ? 12 : 10 }
    private var sectionSize: CGFloat { isLandscape ? 10 : 9 }
    private var rowSize: CGFloat { isLandscape ? 11 : 9 }
    private var closeButtonSize: CGFloat { isLandscape ? 16 : 14 }
    private var columnSpacing: CGFloat { isLandscape ? 20 : 12 }
    private var columnMinWidth: CGFloat { isLandscape ? 160 : 100 }
    private var maxOverlayWidth: CGFloat { isLandscape ? 580 : 280 }
    private var padding: CGFloat { isLandscape ? 12 : 8 }
    private var cornerRadius: CGFloat { isLandscape ? 12 : 10 }
    #endif

    // Colors - adapt to light/dark mode
    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }
    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(isLandscape ? 0.7 : 0.6) : .black.opacity(isLandscape ? 0.7 : 0.6)
    }
    private var tertiaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(isLandscape ? 0.6 : 0.5) : .black.opacity(isLandscape ? 0.6 : 0.5)
    }
    private var labelTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with close button (non-tvOS only - tvOS has button at bottom)
            HStack(spacing: 4) {
                #if os(tvOS)
                Text("MPV Debug Stats")
                    .font(.system(size: headerSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(primaryTextColor)
                #else
                Text(isLandscape ? "MPV Debug" : "Debug")
                    .font(.system(size: headerSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(primaryTextColor)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isVisible = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: closeButtonSize))
                        .foregroundStyle(secondaryTextColor)
                }
                .buttonStyle(.plain)
                #endif
            }
            .padding(.bottom, isLandscape ? 6 : 4)

            // Stats content - always landscape layout on tvOS
            #if os(tvOS)
            landscapeLayout
            #else
            if isLandscape {
                landscapeLayout
            } else {
                portraitLayout
            }
            #endif

            // tvOS close button at bottom
            #if os(tvOS)
            tvOSCloseButton
            #endif
        }
        .padding(padding)
        .glassBackground(.regular, in: .rect(cornerRadius: cornerRadius))
        .shadow(radius: isLandscape ? 8 : 6)
        .frame(maxWidth: maxOverlayWidth)
        #if os(tvOS)
        .onAppear {
            isCloseButtonFocused = true
        }
        .onExitCommand {
            onClose?()
        }
        #endif
    }

    #if os(tvOS)
    @ViewBuilder
    private var tvOSCloseButton: some View {
        Button {
            onClose?()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: closeButtonSize))
                Text("Close")
                    .font(.system(size: rowSize, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(width: 180, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isCloseButtonFocused ? .white.opacity(0.3) : .white.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isCloseButtonFocused ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isCloseButtonFocused)
        .focused($isCloseButtonFocused)
        .padding(.top, 20)
        .frame(maxWidth: .infinity)
    }
    #endif

    // MARK: - Portrait Layout (Compact)

    private var portraitLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left column: Video + Audio
            VStack(alignment: .leading, spacing: 1) {
                videoSectionCompact
                audioSectionCompact
            }

            // Right column: Playback + Cache
            VStack(alignment: .leading, spacing: 1) {
                playbackSectionCompact
                cacheSectionCompact
            }
        }
    }

    // MARK: - Landscape Layout (Detailed)

    private var landscapeLayout: some View {
        HStack(alignment: .top, spacing: columnSpacing) {
            // Column 1: Video
            VStack(alignment: .leading, spacing: 2) {
                videoSectionDetailed
            }
            .frame(minWidth: columnMinWidth)

            // Column 2: Audio + Container
            VStack(alignment: .leading, spacing: 2) {
                audioSectionDetailed
                containerSection
            }
            .frame(minWidth: columnMinWidth)

            // Column 3: Playback + Cache
            VStack(alignment: .leading, spacing: 2) {
                playbackSectionDetailed
                cacheSectionDetailed
            }
            .frame(minWidth: columnMinWidth)

            // Column 4: Video Sync (tvOS frame timing diagnostics)
            #if os(tvOS)
            VStack(alignment: .leading, spacing: 2) {
                videoSyncSection
            }
            .frame(minWidth: columnMinWidth)
            #endif
        }
    }

    // MARK: - Compact Sections (Portrait)

    @ViewBuilder
    private var videoSectionCompact: some View {
        sectionHeader("Video")
        if let codec = stats.videoCodec {
            let hwdec = stats.hwdecCurrent ?? ""
            let codecText = hwdec.isEmpty ? codec : "\(codec) (\(hwdec))"
            statRow("Codec", codecText)
        }
        if let width = stats.width, let height = stats.height {
            statRow("Res", "\(width)×\(height)")
        }
        if let fps = stats.fps {
            if let vfFps = stats.estimatedVfFps {
                statRow("FPS", String(format: "%.2f/%.2f", fps, vfFps))
            } else {
                statRow("FPS", String(format: "%.2f", fps))
            }
        }
    }

    @ViewBuilder
    private var audioSectionCompact: some View {
        sectionHeader("Audio")
        if let codec = stats.audioCodec {
            statRow("Codec", codec)
        }
        if let sampleRate = stats.audioSampleRate, let channels = stats.audioChannels {
            statRow("Format", "\(sampleRate/1000)kHz/\(channels)ch")
        }
    }

    @ViewBuilder
    private var playbackSectionCompact: some View {
        sectionHeader("Playback")
        if let dropped = stats.droppedFrameCount {
            let color: Color = dropped > 0 ? .red : .green
            statRow("Dropped", "\(dropped)", valueColor: color)
        }
        if let sync = stats.avSync {
            let syncMs = sync * 1000
            let color: Color = abs(syncMs) > 50 ? .orange : .green
            statRow("A/V Sync", String(format: "%.1fms", syncMs), valueColor: color)
        }
        if let frame = stats.estimatedFrameNumber {
            statRow("Frame", "\(frame)")
        }
    }

    @ViewBuilder
    private var cacheSectionCompact: some View {
        sectionHeader("Cache")
        if let duration = stats.cacheDuration ?? stats.demuxerCacheDuration {
            statRow("Buffer", String(format: "%.1fs", duration))
        }
        if let bytes = stats.cacheBytes {
            statRow("Size", formatBytes(bytes))
        }
        if let speed = stats.networkSpeed, speed > 0 {
            statRow("Speed", formatBytes(speed) + "/s")
        }
    }

    // MARK: - Detailed Sections (Landscape)

    @ViewBuilder
    private var videoSectionDetailed: some View {
        sectionHeader("Video")
        if let codec = stats.videoCodec {
            stackedRow("Codec", codec)
        }
        if let hwdec = stats.hwdecCurrent, !hwdec.isEmpty {
            stackedRow("HW Decode", hwdec)
        }
        if let width = stats.width, let height = stats.height {
            statRow("Resolution", "\(width)×\(height)")
        }
        if let fps = stats.fps {
            statRow("Container FPS", String(format: "%.3f", fps))
        }
        if let vfFps = stats.estimatedVfFps {
            statRow("Output FPS", String(format: "%.2f", vfFps))
        }
    }

    @ViewBuilder
    private var audioSectionDetailed: some View {
        sectionHeader("Audio")
        if let codec = stats.audioCodec {
            stackedRow("Codec", codec)
        }
        if let sampleRate = stats.audioSampleRate {
            statRow("Sample Rate", "\(sampleRate) Hz")
        }
        if let channels = stats.audioChannels {
            statRow("Channels", "\(channels)")
        }
    }

    @ViewBuilder
    private var containerSection: some View {
        if stats.fileFormat != nil {
            sectionHeader("Container")
            if let format = stats.fileFormat {
                stackedRow("Format", format)
            }
        }
    }

    @ViewBuilder
    private var playbackSectionDetailed: some View {
        sectionHeader("Playback")
        if let dropped = stats.droppedFrameCount {
            let color: Color = dropped > 0 ? .red : .green
            statRow("Dropped Frames", "\(dropped)", valueColor: color)
        }
        if let mistimed = stats.mistimedFrameCount, mistimed > 0 {
            statRow("Mistimed", "\(mistimed)", valueColor: .orange)
        }
        if let delayed = stats.delayedFrameCount, delayed > 0 {
            statRow("Delayed", "\(delayed)", valueColor: .orange)
        }
        if let sync = stats.avSync {
            let syncMs = sync * 1000
            let color: Color = abs(syncMs) > 50 ? .orange : .green
            statRow("A/V Sync", String(format: "%.1f ms", syncMs), valueColor: color)
        }
        if let frame = stats.estimatedFrameNumber {
            statRow("Frame #", "\(frame)")
        }
    }

    @ViewBuilder
    private var cacheSectionDetailed: some View {
        sectionHeader("Cache")
        if let duration = stats.cacheDuration ?? stats.demuxerCacheDuration {
            statRow("Buffer", String(format: "%.1f s", duration))
        }
        if let bytes = stats.cacheBytes {
            statRow("Cache Size", formatBytes(bytes))
        }
        if let speed = stats.networkSpeed, speed > 0 {
            statRow("Network", formatBytes(speed) + "/s")
        }
    }

    // MARK: - Video Sync Section (tvOS)

    #if os(tvOS)
    @ViewBuilder
    private var videoSyncSection: some View {
        sectionHeader("Frame Sync")

        // Video sync mode
        if let videoSync = stats.videoSync {
            stackedRow("Sync Mode", videoSync)
        }

        // Frame drop mode
        if let framedrop = stats.framedrop, !framedrop.isEmpty, framedrop != "no" {
            statRow("Framedrop", framedrop, valueColor: .green)
        }

        // Display FPS (what MPV thinks the display is)
        if let displayFps = stats.displayFps {
            statRow("Display FPS", String(format: "%.2f", displayFps))
        }

        // Display Link target FPS
        if let linkFps = stats.displayLinkFps {
            statRow("Link Target", String(format: "%.1f", linkFps))
        }

        // Speed corrections (show how much MPV is adjusting to match display)
        if let videoCorr = stats.videoSpeedCorrection, abs(videoCorr - 1.0) > 0.0001 {
            let percent = (videoCorr - 1.0) * 100
            let color: Color = abs(percent) > 1 ? .orange : .green
            statRow("Video Speed", String(format: "%+.3f%%", percent), valueColor: color)
        }

        if let audioCorr = stats.audioSpeedCorrection, abs(audioCorr - 1.0) > 0.0001 {
            let percent = (audioCorr - 1.0) * 100
            let color: Color = abs(percent) > 1 ? .orange : .green
            statRow("Audio Speed", String(format: "%+.3f%%", percent), valueColor: color)
        }

        // Vsync jitter (timing consistency)
        if let jitter = stats.vsyncJitter {
            let jitterMs = jitter * 1000
            let color: Color = jitterMs > 2 ? .orange : .green
            statRow("Vsync Jitter", String(format: "%.2f ms", jitterMs), valueColor: color)
        }
    }
    #endif

    // MARK: - Common Components

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: sectionSize, weight: .bold, design: .monospaced))
            .foregroundStyle(tertiaryTextColor)
            .padding(.top, isLandscape ? 6 : 4)
            .padding(.bottom, isLandscape ? 2 : 1)
    }

    @ViewBuilder
    private func statRow(_ label: String, _ value: String, valueColor: Color? = nil) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label)
                .font(.system(size: rowSize - 1, design: .monospaced))
                .foregroundStyle(labelTextColor)
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(value)
                .font(.system(size: rowSize, weight: .medium, design: .monospaced))
                .foregroundStyle(valueColor ?? primaryTextColor)
                .lineLimit(isLandscape ? nil : 1)
                .multilineTextAlignment(.trailing)
        }
    }

    /// Stacked row with label on top and value below - for long values in landscape
    @ViewBuilder
    private func stackedRow(_ label: String, _ value: String, valueColor: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: rowSize - 1, design: .monospaced))
                .foregroundStyle(labelTextColor)
            Text(value)
                .font(.system(size: rowSize, weight: .medium, design: .monospaced))
                .foregroundStyle(valueColor ?? primaryTextColor)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        let gb = mb / 1024

        if gb >= 1 {
            return String(format: "%.2f GB", gb)
        } else if mb >= 1 {
            return String(format: "%.1f MB", mb)
        } else if kb >= 1 {
            return String(format: "%.0f KB", kb)
        } else {
            return "\(bytes) B"
        }
    }
}

// MARK: - Preview

#Preview("Portrait") {
    ZStack {
        Color.black

        MPVDebugOverlay(
            stats: MPVDebugStats(
                videoCodec: "h264",
                hwdecCurrent: "videotoolbox",
                width: 1920,
                height: 1080,
                fps: 29.97,
                estimatedVfFps: 29.94,
                audioCodec: "aac",
                audioSampleRate: 48000,
                audioChannels: 2,
                droppedFrameCount: 0,
                avSync: 0.012,
                cacheDuration: 45.2,
                cacheBytes: 52_428_800,
                networkSpeed: 2_500_000,
                fileFormat: "matroska"
            ),
            isVisible: .constant(true),
            isLandscape: false
        )
    }
}

#Preview("Landscape") {
    ZStack {
        Color.black

        MPVDebugOverlay(
            stats: MPVDebugStats(
                videoCodec: "h264",
                hwdecCurrent: "videotoolbox",
                width: 1920,
                height: 1080,
                fps: 29.97,
                estimatedVfFps: 29.94,
                audioCodec: "aac",
                audioSampleRate: 48000,
                audioChannels: 2,
                droppedFrameCount: 0,
                avSync: 0.012,
                cacheDuration: 45.2,
                cacheBytes: 52_428_800,
                networkSpeed: 2_500_000,
                fileFormat: "matroska"
            ),
            isVisible: .constant(true),
            isLandscape: true
        )
    }
}
