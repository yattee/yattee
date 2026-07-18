//
//  HardwareCapabilities.swift
//  Yattee
//
//  Detects hardware video decoding capabilities using VideoToolbox.
//

import Foundation
import VideoToolbox
import CoreMedia

/// Detects and caches hardware video decoding capabilities for the current device.
@MainActor
final class HardwareCapabilities {
    static let shared = HardwareCapabilities()

    // MARK: - Cached Results

    private var _supportsH264Hardware: Bool?
    private var _supportsHEVCHardware: Bool?
    private var _supportsHEVCAlphaHardware: Bool?
    private var _supportsDolbyVisionHEVCHardware: Bool?
    private var _supportsVP9Hardware: Bool?
    private var _supportsAV1Hardware: Bool?
    private var _supportsProResHardware: Bool?

    // MARK: - Hardware Support Properties

    /// Whether the device supports H.264/AVC hardware decoding.
    var supportsH264Hardware: Bool {
        if let cached = _supportsH264Hardware { return cached }
        let supported = VTIsHardwareDecodeSupported(kCMVideoCodecType_H264)
        _supportsH264Hardware = supported
        return supported
    }

    /// Whether the device supports HEVC/H.265 hardware decoding.
    var supportsHEVCHardware: Bool {
        if let cached = _supportsHEVCHardware { return cached }
        let supported = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        _supportsHEVCHardware = supported
        return supported
    }

    /// Whether the device supports HEVC with Alpha hardware decoding.
    var supportsHEVCAlphaHardware: Bool {
        if let cached = _supportsHEVCAlphaHardware { return cached }
        let supported = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVCWithAlpha)
        _supportsHEVCAlphaHardware = supported
        return supported
    }

    /// Whether the device supports Dolby Vision HEVC hardware decoding.
    var supportsDolbyVisionHEVCHardware: Bool {
        if let cached = _supportsDolbyVisionHEVCHardware { return cached }
        let supported = VTIsHardwareDecodeSupported(kCMVideoCodecType_DolbyVisionHEVC)
        _supportsDolbyVisionHEVCHardware = supported
        return supported
    }

    /// Whether the device supports VP9 hardware decoding.
    var supportsVP9Hardware: Bool {
        if let cached = _supportsVP9Hardware { return cached }
        let supported = VTIsHardwareDecodeSupported(kCMVideoCodecType_VP9)
        _supportsVP9Hardware = supported
        return supported
    }

    /// Whether the device supports AV1 hardware decoding.
    var supportsAV1Hardware: Bool {
        if let cached = _supportsAV1Hardware { return cached }
        let supported = VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
        _supportsAV1Hardware = supported
        return supported
    }

    /// Whether the device supports ProRes hardware decoding.
    var supportsProResHardware: Bool {
        if let cached = _supportsProResHardware { return cached }
        let supported = VTIsHardwareDecodeSupported(kCMVideoCodecType_AppleProRes422)
        _supportsProResHardware = supported
        return supported
    }

    // MARK: - Codec Priority

    /// Returns codec priority for stream selection (higher = better).
    ///
    /// When hardware decode is available, the codec gets a higher priority
    /// to prefer battery-efficient playback. When not available, codecs that
    /// require software decode get priority 0 to prefer hardware-decodable
    /// alternatives at the same or similar resolution.
    ///
    /// Priority levels:
    /// - 4: Best (AV1 with hardware)
    /// - 3: Great (VP9 with hardware, HEVC with hardware)
    /// - 2: Good (H.264 - always hardware supported)
    /// - 1: Acceptable (HEVC software - rare)
    /// - 0: Avoid (AV1/VP9 software - battery drain, potential performance issues)
    func codecPriority(for codec: String?) -> Int {
        guard let codec = codec?.lowercased() else { return 0 }

        if codec.contains("av1") || codec.contains("av01") {
            // AV1: Best compression but avoid without hardware (heavy CPU usage)
            return supportsAV1Hardware ? 4 : 0
        } else if codec.contains("vp9") || codec.contains("vp09") {
            // VP9: Good compression but avoid without hardware (battery drain)
            return supportsVP9Hardware ? 3 : 0
        } else if codec.contains("avc") || codec.contains("h264") || codec.contains("h.264") {
            // H.264: Universal hardware support - reliable choice
            return 2
        } else if codec.contains("hevc") || codec.contains("hev") || codec.contains("h265") || codec.contains("h.265") {
            // HEVC: Good compression, most devices have hardware support
            return supportsHEVCHardware ? 3 : 1
        }
        return 0
    }

    /// Returns an ordered list of preferred codecs based on hardware support.
    var preferredCodecOrder: [String] {
        var codecs: [(String, Int)] = []

        if supportsAV1Hardware {
            codecs.append(("AV1", 4))
        }
        if supportsVP9Hardware {
            codecs.append(("VP9", 3))
        }
        // H.264 is always hardware supported
        codecs.append(("H.264", 2))
        if supportsHEVCHardware {
            codecs.append(("HEVC", 2))
        }

        return codecs.sorted { $0.1 > $1.1 }.map { $0.0 }
    }

    // MARK: - All Capabilities

    /// Returns all codec capabilities for display in Device Capabilities view.
    var allCapabilities: [(name: String, supported: Bool)] {
        [
            ("H.264/AVC", supportsH264Hardware),
            ("HEVC/H.265", supportsHEVCHardware),
            ("HEVC with Alpha", supportsHEVCAlphaHardware),
            ("Dolby Vision HEVC", supportsDolbyVisionHEVCHardware),
            ("VP9", supportsVP9Hardware),
            ("AV1", supportsAV1Hardware),
            ("ProRes", supportsProResHardware)
        ]
    }

    // MARK: - Logging

    /// Logs all hardware capabilities for debugging.
    func logCapabilities() {
        let capabilities = allCapabilities.map { "\($0.name): \($0.supported ? "Yes" : "No")" }.joined(separator: ", ")
        LoggingService.shared.info("Hardware decode capabilities: \(capabilities)", category: .general)
        LoggingService.shared.info("Preferred codec order: \(preferredCodecOrder.joined(separator: " > "))", category: .general)
    }
}
