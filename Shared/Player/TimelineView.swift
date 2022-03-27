import SwiftUI

struct TimelineView: View {
    @Binding private var duration: Double
    @Binding private var current: Double

    @State private var size = CGSize.zero
    @State private var dragging = false
    @State private var dragOffset: Double = 0
    @State private var draggedFrom: Double = 0

    private var start: Double = 0.0
    private var height = 10.0

    var cornerRadius: Double
    var thumbTooltipWidth: Double = 100

    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<PlayerControlsModel> private var controls

    init(duration: Binding<Double>, current: Binding<Double>, cornerRadius: Double = 10.0) {
        _duration = duration
        _current = current
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .foregroundColor(.blue)
                .frame(maxHeight: height)

            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    Color.green
                )
                .frame(maxHeight: height)
                .frame(width: current * oneUnitWidth)

            segmentsLayers

            Circle()
                .strokeBorder(.gray, lineWidth: 1)
                .background(Circle().fill(dragging ? .gray : .white))
                .offset(x: thumbOffset)
                .foregroundColor(.red.opacity(0.6))

                .frame(maxHeight: height * 2)

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
                            current = projectedValue

                            player.backend.seek(to: projectedValue)

                            dragging = false
                            dragOffset = 0.0
                            draggedFrom = 0.0
                            controls.resetTimer()
                        }
                )
            #endif

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .frame(maxWidth: thumbTooltipWidth, maxHeight: 30)

                Text(projectedValue.formattedAsPlaybackTime() ?? "--:--")
                    .foregroundColor(.black)
            }
            .animation(.linear(duration: 0.1))
            .opacity(dragging ? 1 : 0)
            .offset(x: thumbTooltipOffset, y: -(height * 2) - 7)
        }
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear {
                    self.size = proxy.size
                }
                .onChange(of: proxy.size) { size in
                    self.size = size
                }
        })
        #if !os(tvOS)
        .gesture(DragGesture(minimumDistance: 0).onEnded { value in
            let target = (value.location.x / size.width) * units
            current = target
            player.backend.seek(to: target)
        })
        #endif
    }

    var projectedValue: Double {
        let change = (dragOffset / size.width) * units
        let projected = draggedFrom + change
        return projected.isFinite ? projected : start
    }

    var thumbOffset: Double {
        let offset = dragging ? (draggedThumbHorizontalOffset + dragOffset) : thumbHorizontalOffset
        return offset.isFinite ? offset : thumbLeadingOffset
    }

    var thumbTooltipOffset: Double {
        let offset = (dragging ? ((current * oneUnitWidth) + dragOffset) : (current * oneUnitWidth)) - (thumbTooltipWidth / 2)

        return offset.clamped(to: minThumbTooltipOffset ... maxThumbTooltipOffset)
    }

    var minThumbTooltipOffset: Double = -10

    var maxThumbTooltipOffset: Double {
        max(minThumbTooltipOffset, (units * oneUnitWidth) - thumbTooltipWidth + 10)
    }

    var segmentsLayers: some View {
        ForEach(player.sponsorBlock.segments, id: \.uuid) { segment in
            RoundedRectangle(cornerRadius: cornerRadius)
                .offset(x: segmentLayerHorizontalOffset(segment))
                .foregroundColor(.red)
                .frame(maxHeight: height)
                .frame(width: segmentLayerWidth(segment))
        }
    }

    func segmentLayerHorizontalOffset(_ segment: Segment) -> Double {
        segment.start * oneUnitWidth
    }

    func segmentLayerWidth(_ segment: Segment) -> Double {
        let width = segment.duration * oneUnitWidth
        return width.isFinite ? width : thumbLeadingOffset
    }

    var draggedThumbHorizontalOffset: Double {
        thumbLeadingOffset + (draggedFrom * oneUnitWidth)
    }

    var thumbHorizontalOffset: Double {
        thumbLeadingOffset + (current * oneUnitWidth)
    }

    var thumbLeadingOffset: Double {
        -(size.width / 2)
    }

    var oneUnitWidth: Double {
        let one = size.width / units
        return one.isFinite ? one : 0
    }

    var units: Double {
        duration - start
    }

    func setCurrent(_ current: Double) {
        withAnimation {
            self.current = current
        }
    }
}

struct TimelineView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 40) {
            TimelineView(duration: .constant(100), current: .constant(0))
            TimelineView(duration: .constant(100), current: .constant(1))
            TimelineView(duration: .constant(100), current: .constant(30))
            TimelineView(duration: .constant(100), current: .constant(50))
            TimelineView(duration: .constant(100), current: .constant(66))
            TimelineView(duration: .constant(100), current: .constant(90))
            TimelineView(duration: .constant(100), current: .constant(100))
        }
        .padding()
    }
}
