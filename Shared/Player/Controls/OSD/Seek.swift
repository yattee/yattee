import Defaults
import SwiftUI

struct Seek: View {
    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    @ObservedObject private var controls = PlayerControlsModel.shared
    @StateObject private var model = SeekModel.shared

    private var updateThrottle = Throttle(interval: 2)

    @Default(.playerControlsLayout) private var regularPlayerControlsLayout
    @Default(.fullScreenPlayerControlsLayout) private var fullScreenPlayerControlsLayout
    @Default(.sponsorBlockColors) private var sponsorBlockColors
    @Default(.sponsorBlockShowNoticeAfterSkip) private var showNoticeAfterSkip

    private func getColor(for category: String) -> Color {
        if let hexString = sponsorBlockColors[category], let rgbValue = Int(hexString.dropFirst(), radix: 16) {
            let r = Double((rgbValue >> 16) & 0xFF) / 255.0
            let g = Double((rgbValue >> 8) & 0xFF) / 255.0
            let b = Double(rgbValue & 0xFF) / 255.0
            return Color(red: r, green: g, blue: b)
        }
        return Color("AppRedColor") // Fallback color if no match found
    }

    var body: some View {
        Group {
            #if os(tvOS)
                content
                    .shadow(radius: 3)
            #else
                Button(action: model.restoreTime) { content }
                    .buttonStyle(.plain)
            #endif
        }
        .opacity(visible || YatteeApp.isForPreviews ? 1 : 0)
        .animation(.easeIn)
    }

    var content: some View {
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
                        .foregroundColor(getColor(for: segment.category))
                        .padding(.bottom, 3)
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
                            .foregroundColor(getColor(for: category))
                            .padding(.bottom, 3)
                    case let .chapterSkip(chapter):
                        Divider()
                        Text(chapter)
                            .font(.system(size: playerControlsLayout.segmentFontSize))
                            .truncationMode(.tail)
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color("AppRedColor"))
                            .padding(.bottom, 3)
                    default:
                        EmptyView()
                    }
                }
            }
        }
        .frame(maxWidth: playerControlsLayout.seekOSDWidth)
        #if os(tvOS)
            .padding(30)
        #else
            .padding(2)
            .modifier(ControlBackgroundModifier())
            .clipShape(RoundedRectangle(cornerRadius: 3))
        #endif

            .foregroundColor(.primary)
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
        if !showNoticeAfterSkip { if case .segmentSkip? = model.lastSeekType { return false }}

        return !controls.presentingControls && !controls.presentingOverlays && model.presentingOSD
    }

    var projectedChapter: Chapter? {
        (model.player?.currentVideo?.chapters ?? []).last { $0.start <= model.gestureSeekDestinationTime }
    }

    var projectedSegment: Segment? {
        (model.player?.sponsorBlock.segments ?? []).first { $0.timeInSegment(.secondsInDefaultTimescale(model.gestureSeekDestinationTime)) }
    }

    var playerControlsLayout: PlayerControlsLayout {
        (model.player?.playingFullScreen ?? false) ? fullScreenPlayerControlsLayout : regularPlayerControlsLayout
    }
}

struct Seek_Previews: PreviewProvider {
    static var previews: some View {
        Seek()
    }
}
