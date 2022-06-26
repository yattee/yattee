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
            playerTime.currentTime.seconds
        }

        set(value) {
            playerTime.currentTime = .secondsInDefaultTimescale(value)
        }
    }

    @State private var size = CGSize.zero
    @State private var tooltipSize = CGSize.zero
    @State private var dragging = false { didSet {
        if dragging {
            player.backend.stopControlsUpdates()
        } else {
            player.backend.startControlsUpdates()
        }
    }}
    @State private var dragOffset: Double = 0
    @State private var draggedFrom: Double = 0

    private var start: Double = 0.0
    private var height = 8.0

    var cornerRadius: Double
    var thumbAreaWidth: Double = 40
    var context: Context

    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<PlayerControlsModel> private var controls
    @EnvironmentObject<PlayerTimeModel> private var playerTime

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
                        if let segment = projectedSegment,
                           let description = SponsorBlockAPI.categoryDescription(segment.category)
                        {
                            Text(description)
                                .font(.system(size: 8))
                                .fixedSize()
                                .lineLimit(1)
                                .foregroundColor(Color("AppRedColor"))
                        }
                        if let chapter = projectedChapter {
                            Text(chapter.title)
                                .lineLimit(3)
                                .font(.system(size: 11).bold())
                                .frame(maxWidth: 250)
                                .fixedSize()
                        }
                    }
                    Text((dragging ? projectedValue : current).formattedAsPlaybackTime(allowZero: true) ?? PlayerTimeModel.timePlaceholder)
                        .font(.system(size: 11).monospacedDigit())
                }

                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .foregroundColor(.black)
                )

                .foregroundColor(.white)
            }
            .animation(.easeInOut(duration: 0.2))
            .frame(maxHeight: 300, alignment: .bottom)
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

            .frame(height: 80)
            .opacity(dragging ? 1 : 0)
            .animation(.easeOut, value: thumbTooltipOffset)
            HStack(spacing: 4) {
                Text((dragging ? projectedValue : nil)?.formattedAsPlaybackTime(allowZero: true) ?? playerTime.currentPlaybackTime)
                    .frame(minWidth: 35)
                #if os(tvOS)
                    .font(.system(size: 20))
                #endif

                ZStack(alignment: .center) {
                    ZStack(alignment: .leading) {
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.2))
                                .frame(maxHeight: height)
                                .offset(x: current * oneUnitWidth)
                                .zIndex(1)

                            Rectangle()
                                .fill(Color.white.opacity(0.6))
                                .frame(maxHeight: height)
                                .frame(width: current * oneUnitWidth)
                                .zIndex(1)

                            segmentsLayers
                                .zIndex(2)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

                        chaptersLayers
                            .zIndex(3)
                    }

                    Circle()
                        .contentShape(Rectangle())
                        .foregroundColor(.clear)
                        .background(
                            ZStack {
                                Circle()
                                    .fill(dragging ? .white : .gray)
                                    .frame(maxWidth: 8)

                                Circle()
                                    .fill(dragging ? .gray : .white)
                                    .frame(maxWidth: 6)
                            }
                        )
                        .offset(x: thumbOffset)
                        .frame(maxWidth: thumbAreaWidth, minHeight: thumbAreaWidth)

                    #if !os(tvOS)
                        .gesture(
                            DragGesture(minimumDistance: 0)
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
                                    withAnimation(Animation.linear(duration: 0.2)) {
                                        dragOffset = drag
                                    }
                                }
                                .onEnded { _ in
                                    if abs(dragOffset) > 0 {
                                        playerTime.currentTime = .secondsInDefaultTimescale(projectedValue)
                                        player.backend.seek(to: projectedValue)
                                    }

                                    dragging = false
                                    dragOffset = 0.0
                                    draggedFrom = 0.0
                                    controls.resetTimer()
                                }
                        )
                    #endif
                }

                .overlay(GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            self.size = proxy.size
                        }
                        .onChange(of: proxy.size) { size in
                            self.size = size
                        }
                })
                .frame(maxHeight: 20)
                #if !os(tvOS)
                    .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                        let target = (value.location.x / size.width) * units
                        self.playerTime.currentTime = .secondsInDefaultTimescale(target)
                        player.backend.seek(to: target)
                    })
                #endif

                Text(dragging ? playerTime.durationPlaybackTime : playerTime.withoutSegmentsPlaybackTime)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .frame(minWidth: 35)
                #if os(tvOS)
                    .font(.system(size: 20))
                #endif
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .font(.system(size: 9).monospacedDigit())
            .zIndex(2)
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
        let leadingOffset = size.width / 2 - (tooltipSize.width / 2)
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
                .foregroundColor(Color("AppRedColor"))
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
        ForEach(chapters) { chapter in
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.orange)
                .frame(maxWidth: 2, maxHeight: 12)
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
        let playerTimeModel = PlayerTimeModel()
        playerTimeModel.player = playerModel
        playerTimeModel.currentTime = .secondsInDefaultTimescale(33)
        playerTimeModel.duration = .secondsInDefaultTimescale(100)
        return VStack(spacing: 40) {
            TimelineView()
        }
        .environmentObject(playerModel)
        .environmentObject(playerTimeModel)
        .environmentObject(PlayerControlsModel())
        .padding()
    }
}
