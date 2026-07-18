//
//  AVSyncDiagnosticsView.swift
//  Yattee
//
//  tvOS A/V sync debugging controls, pushed as its own page from Advanced settings.
//  - Audio Delay: shifts MPV's `audio-delay` to compensate for fixed HDMI/AVR
//    output pipeline latency. Applies live to a running MPV instance.
//  - Video Sync Mode: A/B between `display-vdrop` (default), `display-resample`,
//    and `audio` modes. Takes effect on next playback start.
//
//  The whole screen is tvOS-only because MPV is the tvOS backend and pipeline
//  latency only differs there; iOS/macOS use the same MPV code path but
//  happen to balance pipeline lag.
//

#if os(tvOS)
import SwiftUI

struct AVSyncDiagnosticsView: View {
    @Bindable var settings: SettingsManager
    @Environment(\.appEnvironment) private var appEnvironment

    private let minDelayMs: Double = -500
    private let maxDelayMs: Double = 500
    private let stepMs: Double = 10

    var body: some View {
        SettingsFormContainer {
            SettingsFormSection(
                footer: "settings.playback.tvSyncDiagnostics.footer"
            ) {
            // Current value as a non-interactive row — tvOS Form rows can't
            // host multiple focusable controls, so we surface the value here
            // and put each control on its own row below.
            HStack {
                Label(
                    String(localized: "settings.playback.tvAudioDelay"),
                    systemImage: "speaker.wave.2.bubble"
                )
                Spacer()
                Text(String(format: "%+.0f ms", settings.tvAudioDelayMs))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            // Coarse steps (±100 ms) first so the user can land near the
            // right value fast, then fine (±10 ms) to dial it in.
            Button {
                adjust(by: -100)
            } label: {
                Label(
                    String(localized: "settings.playback.tvAudioDelay.minus100"),
                    systemImage: "gobackward.minus"
                )
            }
            .disabled(settings.tvAudioDelayMs <= minDelayMs)

            Button {
                adjust(by: -stepMs)
            } label: {
                Label(
                    String(localized: "settings.playback.tvAudioDelay.minus10"),
                    systemImage: "minus"
                )
            }
            .disabled(settings.tvAudioDelayMs <= minDelayMs)

            Button {
                adjust(by: stepMs)
            } label: {
                Label(
                    String(localized: "settings.playback.tvAudioDelay.plus10"),
                    systemImage: "plus"
                )
            }
            .disabled(settings.tvAudioDelayMs >= maxDelayMs)

            Button {
                adjust(by: 100)
            } label: {
                Label(
                    String(localized: "settings.playback.tvAudioDelay.plus100"),
                    systemImage: "goforward.plus"
                )
            }
            .disabled(settings.tvAudioDelayMs >= maxDelayMs)

            Button(role: .destructive) {
                set(to: 0)
            } label: {
                Label(
                    String(localized: "settings.playback.tvAudioDelay.reset"),
                    systemImage: "arrow.counterclockwise"
                )
            }
            .disabled(settings.tvAudioDelayMs == 0)

            PlatformMenuPicker(
                String(localized: "settings.playback.tvVideoSyncMode"),
                selection: $settings.tvVideoSyncMode
            ) {
                    ForEach(TVVideoSyncMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }
        }
    }

    private func adjust(by delta: Double) {
        let next = (settings.tvAudioDelayMs + delta).clamped(to: minDelayMs...maxDelayMs)
        set(to: next)
    }

    private func set(to value: Double) {
        settings.tvAudioDelayMs = value
        if let mpvBackend = appEnvironment?.playerService.currentBackend as? MPVBackend {
            mpvBackend.updateAudioDelay(milliseconds: value)
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
#endif
