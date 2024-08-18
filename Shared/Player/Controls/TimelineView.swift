import Defaults
import SwiftUI

struct TimelineView: View {
    enum Context {
        case controls
        case player
    }

    private var duration: Double {
        playerTime.duration.seconds
    }

    private var current: Double {
        get {
            max(0, playerTime.currentTime.seconds)
        }

        set(value) {
            playerTime.currentTime = .secondsInDefaultTimescale(value)
        }
    }

    @State private var size = CGSize.zero
    @State private var tooltipSize = CGSize.zero
    @State private var dragging = false { didSet {
        if dragging, player.backend.controlsUpdates {
            player.backend.stopControlsUpdates()
        } else if !dragging, !player.backend.controlsUpdates {
            player.backend.startControlsUpdates()
        }
    }}
    @State private var dragOffset: Double = 0
    @State private var draggedFrom: Double = 0

    private var start = 0.0
    private var height = 8.0

    var cornerRadius: Double
    var thumbAreaWidth: Double = 40
    var context: Context

    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    @ObservedObject private var playerTime = PlayerTimeModel.shared
    @ObservedObject private var player = PlayerModel.shared

    private var controls = PlayerControlsModel.shared

    @Default(.playerControlsLayout) private var regularPlayerControlsLayout
    @Default(.fullScreenPlayerControlsLayout) private var fullScreenPlayerControlsLayout
    @Default(.sponsorBlockColors) private var sponsorBlockColors
    @Default(.sponsorBlockShowTimeWithSkipsRemoved) private var showTimeWithSkipsRemoved
    @Default(.sponsorBlockShowCategoriesInTimeline) private var showCategoriesInTimeline

    var playerControlsLayout: PlayerControlsLayout {
        player.playingFullScreen ? fullScreenPlayerControlsLayout : regularPlayerControlsLayout
    }

    private func getColor(for category: String) -> Color {
        if let hexString = sponsorBlockColors[category], let rgbValue = Int(hexString.dropFirst(), radix: 16) {
            let r = Double((rgbValue >> 16) & 0xFF) / 255.0
            let g = Double((rgbValue >> 8) & 0xFF) / 255.0
            let b = Double(rgbValue & 0xFF) / 255.0
            return Color(red: r, green: g, blue: b)
        }
        return Color("AppRedColor") // Fallback color if no match found
    }

    var chapters: [Chapter] {
        player.currentVideo?.chapters ?? []
    }

    init(
        cornerRadius: Double = 10.0,
        context: Context = .controls
    ) {
        self.cornerRadius = cornerRadius
        self.context = context
    }

    var body: some View {
        VStack {
            Group {
                VStack(spacing: 3) {
                    if dragging {
                        if showCategoriesInTimeline {
                            if let segment = projectedSegment,
                               let description = SponsorBlockAPI.categoryDescription(segment.category)
                            {
                                Text(description)
                                    .font(.system(size: playerControlsLayout.segmentFontSize))
                                    .fixedSize()
                                    .foregroundColor(getColor(for: segment.category))
                            }
                        }
                        if let chapter = projectedChapter {
                            Text(chapter.title)
                                .lineLimit(3)
                                .font(.system(size: playerControlsLayout.chapterFontSize).bold())
                                .frame(maxWidth: player.playerSize.width - 100)
                                .fixedSize()
                        }
                    }
                    Text((dragging ? projectedValue : current).formattedAsPlaybackTime(allowZero: true, forceHours: playerTime.forceHours) ?? PlayerTimeModel.timePlaceholder)
                        .font(.system(size: playerControlsLayout.projectedTimeFontSize).monospacedDigit())
                }
                .animation(.easeIn(duration: 0.2), value: projectedChapter)
                .animation(.easeIn(duration: 0.2), value: projectedSegment)
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .foregroundColor(.black)
                )

                .foregroundColor(.white)
            }
            #if os(tvOS)
            .frame(maxHeight: 300, alignment: .bottom)
            #endif
            .offset(x: thumbTooltipOffset)
            .overlay(GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        tooltipSize = proxy.size
                    }
                    .onChange(of: proxy.size) { _ in
                        tooltipSize = proxy.size
                    }
            })
            #if os(tvOS)
            .frame(height: 80)
            #endif
            .opacity(dragging ? 1 : 0)
            .animation(.easeOut, value: thumbTooltipOffset)
            HStack(spacing: 4) {
                Text((dragging ? projectedValue : nil)?.formattedAsPlaybackTime(allowZero: true, forceHours: playerTime.forceHours) ?? playerTime.currentPlaybackTime)
                    .opacity(player.liveStreamInAVPlayer ? 0 : 1)
                    .frame(minWidth: 35)
                    .padding(.leading, playerControlsLayout.timeLeadingEdgePadding)
                    .padding(.trailing, playerControlsLayout.timeTrailingEdgePadding)
                    .shadow(radius: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                ZStack {
                    ZStack(alignment: .leading) {
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.2))
                                .frame(maxHeight: height)
                                .offset(x: (dragging ? projectedValue : current) * oneUnitWidth)
                                .zIndex(1)

                            Rectangle()
                                .fill(Color.white.opacity(0.6))
                                .frame(maxHeight: height)
                                .frame(width: (dragging ? projectedValue : current) * oneUnitWidth)
                                .zIndex(1)

                            if showCategoriesInTimeline {
                                segmentsLayers
                                    .zIndex(2)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

                        chaptersLayers
                            .zIndex(3)
                    }
                }
                .opacity(player.liveStreamInAVPlayer ? 0 : 1)
                .overlay(GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            self.size = proxy.size
                        }
                        .onChange(of: proxy.size) { size in
                            self.size = size
                        }
                })

                durationView
                    .shadow(radius: 3)
                    .padding(.leading, playerControlsLayout.timeTrailingEdgePadding)
                    .padding(.trailing, playerControlsLayout.timeLeadingEdgePadding)
                    .frame(minWidth: 30, alignment: .trailing)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            .font(.system(size: playerControlsLayout.timeFontSize).monospacedDigit())
            .zIndex(2)
            .foregroundColor(.white)
        }
        .contentShape(Rectangle())
        #if !os(tvOS)
            .gesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .global)
                    .onChanged { value in
                        if !dragging {
                            controls.removeTimer()
                            draggedFrom = current
                        }

                        dragging = true

                        let drag = value.translation.width
                        let change = (drag / size.width) * units
                        let changedCurrent = current + change

                        guard changedCurrent >= start, changedCurrent <= duration else {
                            return
                        }

                        dragOffset = drag
                    }
                    .onEnded { _ in
                        if abs(dragOffset) > 0 {
                            playerTime.currentTime = .secondsInDefaultTimescale(projectedValue)
                            player.backend.seek(to: projectedValue, seekType: .userInteracted)
                        }

                        dragging = false
                        dragOffset = 0.0
                        draggedFrom = 0.0
                        controls.resetTimer()
                    }
            )
        #endif
    }

    @ViewBuilder var durationView: some View {
        if player.live {
            if player.playingLive || player.activeBackend == .appleAVPlayer {
                Text("LIVE")
                    .fontWeight(.bold)
                    .padding(2)
                    .foregroundColor(.white)
                    .background(RoundedRectangle(cornerRadius: 2).foregroundColor(.red))
            } else {
                Button {
                    if let duration = player.videoDuration {
                        player.backend.seek(to: duration - 5, seekType: .userInteracted)
                    }
                } label: {
                    Text("LIVE")
                        .fontWeight(.bold)
                        .padding(2)
                        .foregroundColor(.primary)
                        .background(RoundedRectangle(cornerRadius: 2).strokeBorder(.red, lineWidth: 1).foregroundColor(.white))
                }
            }
        } else {
            Text(dragging || !showTimeWithSkipsRemoved ? playerTime.durationPlaybackTime : playerTime.withoutSegmentsPlaybackTime)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .frame(minWidth: 35)
        }
    }

    var tooltipVeritcalOffset: Double {
        var offset = -20.0

        if !projectedChapter.isNil {
            offset -= 8.0
        }

        if !projectedSegment.isNil {
            offset -= 6.5
        }

        return offset
    }

    var projectedValue: Double {
        let change = (dragOffset / size.width) * units
        let projected = draggedFrom + change

        guard projected.isFinite && projected >= 0 && projected <= duration else {
            return 0.0
        }

        return projected.clamped(to: 0 ... duration)
    }

    var thumbOffset: Double {
        let offset = dragging ? draggedThumbHorizontalOffset : thumbHorizontalOffset
        return offset.isFinite ? offset : thumbLeadingOffset
    }

    var thumbTooltipOffset: Double {
        let leadingOffset = abs(size.width / 2 - (tooltipSize.width / 2))
        let offsetForThumb = thumbOffset - thumbLeadingOffset

        guard offsetForThumb > tooltipSize.width / 2 else {
            return -leadingOffset
        }

        return thumbOffset.clamped(to: -leadingOffset ... leadingOffset)
    }

    var minThumbTooltipOffset: Double {
        60
    }

    var maxThumbTooltipOffset: Double {
        max(minThumbTooltipOffset, units * oneUnitWidth)
    }

    var segments: [Segment] {
        player.sponsorBlock.segments
    }

    var segmentsLayers: some View {
        ForEach(segments, id: \.uuid) { segment in
            Rectangle()
                .offset(x: segmentLayerHorizontalOffset(segment))
                .foregroundColor(getColor(for: segment.category))
                .frame(maxHeight: height)
                .frame(width: segmentLayerWidth(segment))
        }
    }

    var projectedSegment: Segment? {
        segments.first { $0.timeInSegment(.secondsInDefaultTimescale(projectedValue)) }
    }

    var projectedChapter: Chapter? {
        chapters.last { $0.start <= projectedValue }
    }

    var chaptersLayers: some View {
        ForEach(chapters.filter { $0.start != 0 }) { chapter in
            RoundedRectangle(cornerRadius: 4)
                .fill(Color("AppRedColor"))
                .frame(maxWidth: 2, maxHeight: height)
                .offset(x: (chapter.start * oneUnitWidth) - 1)
        }
    }

    func segmentLayerHorizontalOffset(_ segment: Segment) -> Double {
        segment.start * oneUnitWidth
    }

    func segmentLayerWidth(_ segment: Segment) -> Double {
        let width = segment.duration * oneUnitWidth
        return width.isFinite ? width : 1
    }

    var draggedThumbHorizontalOffset: Double {
        thumbLeadingOffset + (draggedFrom * oneUnitWidth) + dragOffset
    }

    var thumbHorizontalOffset: Double {
        thumbLeadingOffset + (current * oneUnitWidth)
    }

    var thumbLeadingOffset: Double {
        -size.width / 2
    }

    var oneUnitWidth: Double {
        let one = size.width / units
        return one.isFinite ? one : 0
    }

    var units: Double {
        duration - start
    }
}

struct TimelineView_Previews: PreviewProvider {
    static var duration = 100.0
    static var current = 0.0
    static var durationBinding: Binding<Double> = .init(
        get: { duration },
        set: { value in duration = value }
    )
    static var currentBinding = Binding<Double>(
        get: { current },
        set: { value in current = value }
    )

    static var previews: some View {
        let playerModel = PlayerModel()
        playerModel.currentItem = .init(Video.fixture)
        let playerTimeModel = PlayerTimeModel.shared
        playerTimeModel.currentTime = .secondsInDefaultTimescale(33)
        playerTimeModel.duration = .secondsInDefaultTimescale(100)
        return VStack(spacing: 40) {
            TimelineView()
        }
        .background(Color.black)
        .padding()
    }
}
