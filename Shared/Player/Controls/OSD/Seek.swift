import Defaults
import SwiftUI

struct Seek: View {
    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    @EnvironmentObject<PlayerControlsModel> private var controls
    @EnvironmentObject<PlayerTimeModel> private var model

    @State private var dismissTimer: Timer?
    @State private var isSeeking = false

    private var updateThrottle = Throttle(interval: 2)

    @Default(.playerControlsLayout) private var regularPlayerControlsLayout
    @Default(.fullScreenPlayerControlsLayout) private var fullScreenPlayerControlsLayout

    var body: some View {
        Button(action: model.restoreTime) {
            VStack(spacing: playerControlsLayout.osdSpacing) {
                ProgressBar(value: progress)
                    .frame(maxHeight: playerControlsLayout.osdProgressBarHeight)

                timeline

                if isSeeking {
                    Divider()
                    gestureSeekTime
                        .foregroundColor(.secondary)
                        .font(.system(size: playerControlsLayout.chapterFontSize).monospacedDigit())
                        .frame(height: playerControlsLayout.chapterFontSize + 5)

                    if let chapter = projectedChapter {
                        Divider()
                        Text(chapter.title)
                            .multilineTextAlignment(.center)
                            .font(.system(size: playerControlsLayout.chapterFontSize))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let segment = projectedSegment {
                        Text(SponsorBlockAPI.categoryDescription(segment.category) ?? "Sponsor")
                            .font(.system(size: playerControlsLayout.segmentFontSize))
                            .foregroundColor(Color("AppRedColor"))
                    }
                } else {
                    #if !os(tvOS)
                        if !model.restoreSeekTime.isNil {
                            Divider()
                            Label(model.restoreSeekPlaybackTime, systemImage: "arrow.counterclockwise")
                                .foregroundColor(.secondary)
                                .font(.system(size: playerControlsLayout.chapterFontSize).monospacedDigit())
                                .frame(height: playerControlsLayout.chapterFontSize + 5)
                        }
                    #endif
                    Group {
                        switch model.lastSeekType {
                        case let .segmentSkip(category):
                            Divider()
                            Text(SponsorBlockAPI.categoryDescription(category) ?? "Sponsor")
                                .font(.system(size: playerControlsLayout.segmentFontSize))
                                .foregroundColor(Color("AppRedColor"))
                        default:
                            EmptyView()
                        }
                    }
                }
            }
            #if os(tvOS)
            .frame(minWidth: 250, minHeight: 100)
            .padding(30)
            #endif
            .frame(maxWidth: playerControlsLayout.seekOSDWidth)
            .padding(2)
            .modifier(ControlBackgroundModifier())
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .foregroundColor(.primary)
        }
        #if os(tvOS)
        .fixedSize()
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
        .opacity(visible || YatteeApp.isForPreviews ? 1 : 0)
        .onChange(of: model.lastSeekTime) { _ in
            isSeeking = false
            dismissTimer?.invalidate()
            dismissTimer = Delay.by(3) {
                withAnimation(.easeIn(duration: 0.1)) { model.seekOSDDismissed = true }
            }

            if model.seekOSDDismissed {
                withAnimation(.easeIn(duration: 0.1)) { self.model.seekOSDDismissed = false }
            }
        }
        .onChange(of: model.gestureSeek) { newValue in
            let newIsSeekingValue = isSeeking || model.gestureSeek != 0
            if !isSeeking, newIsSeekingValue {
                model.onSeekGestureStart()
            }
            isSeeking = newIsSeekingValue
            guard newValue != 0 else { return }
            updateThrottle.execute {
                model.player.backend.getTimeUpdates()
                model.player.backend.updateControls()
            }

            dismissTimer?.invalidate()
            if model.seekOSDDismissed {
                withAnimation(.easeIn(duration: 0.1)) { self.model.seekOSDDismissed = false }
            }
        }
    }

    var timeline: some View {
        let text = model.gestureSeek != 0 && model.lastSeekTime.isNil ?
            "\(model.gestureSeekDestinationPlaybackTime)/\(model.durationPlaybackTime)" :
            "\(model.lastSeekPlaybackTime)/\(model.durationPlaybackTime)"

        return Text(text)
            .fontWeight(.bold)
            .font(.system(size: playerControlsLayout.projectedTimeFontSize).monospacedDigit())
    }

    var gestureSeekTime: some View {
        var seek = model.gestureSeekDestinationTime - model.currentTime.seconds
        if seek > 0 {
            seek = min(seek, model.duration.seconds - model.currentTime.seconds)
        } else {
            seek = min(seek, model.currentTime.seconds)
        }
        let timeText = abs(seek)
            .formattedAsPlaybackTime(allowZero: true, forceHours: model.forceHours) ?? ""

        return Label(
            timeText,
            systemImage: seek >= 0 ? "goforward.plus" : "gobackward.minus"
        )
    }

    var visible: Bool {
        guard !(model.lastSeekTime.isNil && !isSeeking) else { return false }
        if let type = model.lastSeekType, !type.presentable { return false }

        return !controls.presentingControls && !controls.presentingOverlays && !model.seekOSDDismissed
    }

    var progress: Double {
        if isSeeking {
            return model.gestureSeekDestinationTime / model.duration.seconds
        }

        guard model.duration.seconds.isFinite, model.duration.seconds > 0 else { return 0 }
        guard let seekTime = model.lastSeekTime else { return model.currentTime.seconds / model.duration.seconds }

        return seekTime.seconds / model.duration.seconds
    }

    var projectedChapter: Chapter? {
        (model.player?.currentVideo?.chapters ?? []).last { $0.start <= model.gestureSeekDestinationTime }
    }

    var projectedSegment: Segment? {
        (model.player?.sponsorBlock.segments ?? []).first { $0.timeInSegment(.secondsInDefaultTimescale(model.gestureSeekDestinationTime)) }
    }

    var playerControlsLayout: PlayerControlsLayout {
        fullScreenLayout ? fullScreenPlayerControlsLayout : regularPlayerControlsLayout
    }

    var fullScreenLayout: Bool {
        guard let player = model.player else { return false }
        #if os(iOS)
            return player.playingFullScreen || verticalSizeClass == .compact
        #else
            return player.playingFullScreen
        #endif
    }
}

struct Seek_Previews: PreviewProvider {
    static var previews: some View {
        Seek()
            .environmentObject(PlayerTimeModel())
    }
}
