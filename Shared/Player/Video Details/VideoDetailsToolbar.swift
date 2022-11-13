import SwiftUI

struct VideoDetailsToolbar: View {
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

    var body: some View {
        Group {
            VStack {
                HStack(spacing: 12) {
                    ForEach($tools) { $tool in
                        if $tool.wrappedValue.isAvailable(for: video, sidebarQueue: sidebarQueue) {
                            ToolView(tool: $tool)
                                .padding(.vertical, 10)
                        }
                    }
                }
                .onChange(of: page) { newValue in
                    activeTool = tools.first { $0.id == newValue.rawValue }
                }
                .coordinateSpace(name: "toolbarArea")
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
                                withAnimation(.easeOut(duration: 1)) {
                                    opacity = 0.1
                                }
                            }
                        }
                )
            }
            .onAppear {
                Delay.by(2) {
                    withAnimation(.linear(duration: 1)) {
                        opacity = 0.1
                    }
                }
            }
            .opacity(opacity)
        }
        .background(
            Rectangle()
                .contentShape(Rectangle())
                .foregroundColor(.clear)
        )
        .onHover { hovering in
            withAnimation(.linear(duration: 0.1)) {
                opacity = hovering ? 1 : 0.1
            }
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

            if activeToolID == tool.wrappedValue.id, false {
                Text(tool.wrappedValue.name)
                    .font(.system(size: 14).bold())
                    .foregroundColor(.white)
                    .allowsTightening(true)
                    .lineLimit(1)
                    .layoutPriority(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(activeToolID == tool.wrappedValue.id ? Color.accentColor : Color.secondary)
        )
    }

    var activeToolID: VideoDetailsTool.ID {
        activeTool?.id ?? "queue"
    }
}
