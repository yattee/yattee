import Defaults
import SwiftUI

struct VideoDetailsToolbar: View {
    static let lowOpacity = 0.5
    var video: Video?
    @Binding var page: VideoDetails.DetailsPage
    var sidebarQueue: Bool

    @State private var tools: [VideoDetailsTool] = [
        .init(icon: "info.circle", name: "Info", page: .info),
        .init(icon: "wand.and.stars", name: "Inspector", page: .inspector),
        .init(icon: "bookmark", name: "Chapters", page: .chapters),
        .init(icon: "text.bubble", name: "Comments", page: .comments),
        .init(icon: "rectangle.stack.fill", name: "Related", page: .related),
        .init(icon: "list.number", name: "Queue", page: .queue)
    ]

    @State private var activeTool: VideoDetailsTool?
    @State private var startedToolPosition: CGRect = .zero
    @State private var opacity = 1.0

    @EnvironmentObject<PlayerModel> private var player
    @Default(.playerDetailsPageButtonLabelStyle) private var playerDetailsPageButtonLabelStyle

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                ForEach($tools) { $tool in
                    if $tool.wrappedValue.isAvailable(for: video, sidebarQueue: sidebarQueue) {
                        ToolView(tool: $tool)
                            .padding(.vertical, 10)
                    }
                }
            }
            .id(video?.id)
            .onChange(of: page) { newValue in
                activeTool = tools.first { $0.id == newValue.rawValue }
            }
            .coordinateSpace(name: "toolbarArea")
            #if !os(tvOS)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            withAnimation(.linear(duration: 0.2)) {
                                opacity = 1
                            }

                            guard let firstTool = tools.first else { return }
                            if startedToolPosition == .zero {
                                startedToolPosition = firstTool.toolPostion
                            }
                            let location = CGPoint(x: value.location.x, y: value.location.y)

                            if let index = tools.firstIndex(where: { $0.toolPostion.contains(location) }),
                               activeTool?.id != tools[index].id,
                               tools[index].isAvailable(for: video, sidebarQueue: sidebarQueue)
                            {
                                withAnimation(.interpolatingSpring(stiffness: 230, damping: 22)) {
                                    activeTool = tools[index]
                                }
                                withAnimation(.linear(duration: 0.25)) {
                                    page = activeTool?.page ?? .info
                                }
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.interactiveSpring(response: 0.5, dampingFraction: 1, blendDuration: 1)) {
                                startedToolPosition = .zero
                            }
                            Delay.by(2) {
                                lowerOpacity()
                            }
                        }
                )
            #endif
        }
        #if !os(tvOS)
        .onHover { hovering in
            hovering ? resetOpacity(0.2) : lowerOpacity(0.2)
        }
        #endif
        .onAppear {
            Delay.by(2) { lowerOpacity() }
        }
        .opacity(opacity)
        .background(
            Rectangle()
                .contentShape(Rectangle())
                .foregroundColor(.clear)
        )
    }

    func lowerOpacity(_ duration: Double = 1.0) {
        withAnimation(.linear(duration: duration)) {
            opacity = Self.lowOpacity
        }
    }

    func resetOpacity(_ duration: Double = 1.0) {
        withAnimation(.linear(duration: duration)) {
            opacity = 1
        }
    }

    @ViewBuilder func ToolView(tool: Binding<VideoDetailsTool>) -> some View {
        HStack(spacing: 0) {
            Image(systemName: tool.wrappedValue.icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .layoutPriority(1)

                .background(
                    GeometryReader { proxy in
                        let frame = proxy.frame(in: .named("toolbarArea"))
                        Color.clear
                            .preference(key: RectKey.self, value: frame)
                            .onPreferenceChange(RectKey.self) { rect in
                                tool.wrappedValue.toolPostion = rect
                            }
                    }
                )

            if activeToolID == tool.wrappedValue.id,
               playerDetailsPageButtonLabelStyle.text,
               player.playerSize.width > 450
            {
                Text(tool.wrappedValue.name)
                    .font(.system(size: 14).bold())
                    .padding(.trailing, 4)
                    .foregroundColor(.white)
                    .allowsTightening(true)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(activeToolID == tool.wrappedValue.id ? Color.accentColor : Color.secondary)
        )
    }

    var visibleToolsCount: Int {
        tools.filter { $0.isAvailable(for: video, sidebarQueue: sidebarQueue) }.count
    }

    var activeToolID: VideoDetailsTool.ID {
        activeTool?.id ?? "queue"
    }
}

struct VideoDetailsToolbar_Previews: PreviewProvider {
    static var previews: some View {
        VideoDetailsToolbar(page: .constant(.queue), sidebarQueue: false)
            .injectFixtureEnvironmentObjects()
    }
}
