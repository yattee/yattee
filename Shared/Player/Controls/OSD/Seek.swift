import Defaults
import SwiftUI

struct Seek: View {
    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    @EnvironmentObject<PlayerControlsModel> private var controls
    @EnvironmentObject<SeekModel> private var model

    private var updateThrottle = Throttle(interval: 2)

    @Default(.playerControlsLayout) private var regularPlayerControlsLayout
    @Default(.fullScreenPlayerControlsLayout) private var fullScreenPlayerControlsLayout

    var body: some View {
        Button(action: model.restoreTime) {
            VStack(spacing: playerControlsLayout.osdSpacing) {
                ProgressBar(value: model.progress)
                    .frame(maxHeight: playerControlsLayout.osdProgressBarHeight)

                timeline

                if model.isSeeking {
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
    }

    var timeline: some View {
        let text = model.isSeeking ?
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
        guard !(model.lastSeekTime.isNil && !model.isSeeking) else { return false }
        if let type = model.lastSeekType, !type.presentable { return false }

        return !controls.presentingControls && !controls.presentingOverlays && model.presentingOSD
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
