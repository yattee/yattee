//
//  TVDisplayModeManager.swift
//  Yattee
//
//  Drives AVDisplayManager.preferredDisplayCriteria on tvOS so the Apple TV
//  switches its HDMI output to match the playing video's frame rate and
//  dynamic range. Independent of the playback engine — works alongside MPV.
//
//  The user must also have "Match Content → Frame Rate / Dynamic Range" enabled
//  in tvOS Settings → Video and Audio for the system to honor these criteria.
//

#if os(tvOS)
import AVFoundation
import AVKit
import CoreMedia
import UIKit

enum TVDisplayDynamicRange {
    case sdr
    case hdr10
    case hlg

    var transferFunction: CFString {
        switch self {
        case .sdr: return kCMFormatDescriptionTransferFunction_ITU_R_709_2
        case .hdr10: return kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ
        case .hlg: return kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG
        }
    }

    var colorPrimaries: CFString {
        switch self {
        case .sdr: return kCMFormatDescriptionColorPrimaries_ITU_R_709_2
        case .hdr10, .hlg: return kCMFormatDescriptionColorPrimaries_ITU_R_2020
        }
    }

    var yCbCrMatrix: CFString {
        switch self {
        case .sdr: return kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2
        case .hdr10, .hlg: return kCMFormatDescriptionYCbCrMatrix_ITU_R_2020
        }
    }
}

/// Maps an MPV `video-params/gamma` string to the closest tvOS dynamic-range bucket.
/// MPV exposes gammas like `bt.1886`, `srgb`, `pq`, `hlg`. Anything we don't recognize
/// is treated as SDR.
func tvDisplayDynamicRange(fromMPVGamma gamma: String?) -> TVDisplayDynamicRange {
    switch gamma?.lowercased() {
    case "pq", "smpte2084", "st2084":
        return .hdr10
    case "hlg", "arib-std-b67":
        return .hlg
    default:
        return .sdr
    }
}

@MainActor
final class TVDisplayModeManager {
    static let shared = TVDisplayModeManager()

    /// Anchors a real AVKit ObjC class symbol so the linker keeps AVKit linked.
    /// Without this, AVKit's UIWindow category that adds `avDisplayManager` is
    /// not loaded at runtime and the selector crashes — Swift only autolinks
    /// AVFoundation here because `AVDisplayCriteria` lives there.
    private static let _avkitLinkAnchor: AnyClass = AVDisplayManager.self

    private var hasAppliedCriteria = false

    private init() {
        _ = Self._avkitLinkAnchor
    }

    /// Apply preferred display criteria for the given video parameters.
    /// Pass `nil` for fields you don't have yet; this method is safe to call
    /// repeatedly as more info becomes available (e.g. fps arrives before gamma).
    func apply(fps: Double?, gamma: String?) {
        let matchFrameRate = readBool(key: "tvMatchDisplayFrameRate", default: false)
        let matchDynamicRange = readBool(key: "tvMatchDisplayDynamicRange", default: false)

        guard matchFrameRate || matchDynamicRange else {
            clear()
            return
        }

        let refreshRate: Float = (matchFrameRate ? Float(fps ?? 0) : 0)
        let dynamicRange = matchDynamicRange ? tvDisplayDynamicRange(fromMPVGamma: gamma) : nil

        // If we have neither dimension to actually request, no-op.
        guard refreshRate > 0 || dynamicRange != nil else { return }

        guard let manager = activeDisplayManager() else {
            LoggingService.shared.debug(
                "TVDisplayMode: no AVDisplayManager available (no UIWindowScene yet)",
                category: .mpv
            )
            return
        }

        let criteria: AVDisplayCriteria
        if let dynamicRange {
            let formatDescription = makeFormatDescription(for: dynamicRange)
            criteria = AVDisplayCriteria(
                refreshRate: refreshRate,
                formatDescription: formatDescription
            )
        } else {
            // Frame-rate only: use BT.709/SDR format description so the system
            // doesn't switch dynamic range.
            let formatDescription = makeFormatDescription(for: .sdr)
            criteria = AVDisplayCriteria(
                refreshRate: refreshRate,
                formatDescription: formatDescription
            )
        }

        manager.preferredDisplayCriteria = criteria
        hasAppliedCriteria = true
        LoggingService.shared.debug(
            "TVDisplayMode: applied refreshRate=\(refreshRate), dynamicRange=\(dynamicRange.map(String.init(describing:)) ?? "nil")",
            category: .mpv
        )
    }

    /// Clear any previously-applied criteria so tvOS reverts to the user's default mode.
    func clear() {
        guard hasAppliedCriteria else { return }
        hasAppliedCriteria = false
        guard let manager = activeDisplayManager() else { return }
        manager.preferredDisplayCriteria = nil
        LoggingService.shared.debug("TVDisplayMode: cleared", category: .mpv)
    }

    // MARK: - Helpers

    private func readBool(key: String, default defaultValue: Bool) -> Bool {
        // The SettingsManager stores these unprefixed (not platform-specific keys),
        // so we can read them directly from standard UserDefaults.
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return defaultValue
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    private func activeDisplayManager() -> AVDisplayManager? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        return window?.avDisplayManager
    }

    private func makeFormatDescription(for dynamicRange: TVDisplayDynamicRange) -> CMVideoFormatDescription {
        let extensions: [CFString: Any] = [
            kCMFormatDescriptionExtension_TransferFunction: dynamicRange.transferFunction,
            kCMFormatDescriptionExtension_ColorPrimaries: dynamicRange.colorPrimaries,
            kCMFormatDescriptionExtension_YCbCrMatrix: dynamicRange.yCbCrMatrix
        ]

        var description: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_HEVC,
            width: 1920,
            height: 1080,
            extensions: extensions as CFDictionary,
            formatDescriptionOut: &description
        )
        // CMVideoFormatDescriptionCreate cannot meaningfully fail with these inputs,
        // but if it does, fall back to a minimal description AVDisplayCriteria can use.
        if let description {
            return description
        }
        var fallback: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_HEVC,
            width: 1920,
            height: 1080,
            extensions: nil,
            formatDescriptionOut: &fallback
        )
        return fallback!
    }
}
#endif
