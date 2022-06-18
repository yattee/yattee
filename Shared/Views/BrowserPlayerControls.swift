import Foundation
import SDWebImageSwiftUI
import SwiftUI

struct BrowserPlayerControls<Content: View, Toolbar: View>: View {
    enum Context {
        case browser, player
    }

    let content: Content

    init(
        context _: Context? = nil,
        @ViewBuilder toolbar: @escaping () -> Toolbar? = { nil },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.content = content()
    }

    init(
        context: Context? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) where Toolbar == EmptyView {
        self.init(context: context, toolbar: { EmptyView() }, content: content)
    }

    var body: some View {
        if #available(iOS 15.0, macOS 12.0, *) {
            _ = Self._printChanges()
        }

        return VStack(spacing: 0) {
            content

            #if !os(tvOS)
                ControlsBar()
                    .edgesIgnoringSafeArea(.bottom)
            #endif
        }
    }
}

// struct BrowserPlayerControls<Content: View, Toolbar: View>: View {
//    enum Context {
//        case browser, player
//    }
//
//    let context: Context
//    let content: Content
//    let toolbar: Toolbar?
//
//    @Environment(\.navigationStyle) private var navigationStyle
//    @EnvironmentObject<PlayerControlsModel> private var playerControls
//    @EnvironmentObject<PlayerModel> private var model
//
//    var barHeight: Double {
//        75
//    }
//
//    init(
//        context: Context? = nil,
//        @ViewBuilder toolbar: @escaping () -> Toolbar? = { nil },
//        @ViewBuilder content: @escaping () -> Content
//    ) {
//        self.context = context ?? .browser
//        self.content = content()
//        self.toolbar = toolbar()
//    }
//
//    init(
//        context: Context? = nil,
//        @ViewBuilder content: @escaping () -> Content
//    ) where Toolbar == EmptyView {
//        self.init(context: context, toolbar: { EmptyView() }, content: content)
//    }
//
//    var body: some View {
//        ZStack(alignment: .bottomLeading) {
//            VStack(spacing: 0) {
//                content
//
//                Color.clear.frame(height: barHeight)
//            }
//            #if !os(tvOS)
//            .frame(minHeight: 0, maxHeight: .infinity)
//            #endif
//
//
//            VStack {
//                #if !os(tvOS)
//                    #if !os(macOS)
//                        toolbar
//                            .frame(height: 100)
//                            .offset(x: 0, y: -28)
//                    #endif
//
//                if context != .player || !playerControls.playingFullscreen {
//                    controls
//                }
//                #endif
//            }
//            .borderTop(height: 0.4, color: Color("ControlsBorderColor"))
//            #if os(macOS)
//                .background(VisualEffectBlur(material: .sidebar))
//            #elseif os(iOS)
//                .background(VisualEffectBlur(blurStyle: .systemThinMaterial).edgesIgnoringSafeArea(.all))
//            #endif
//        }
//        .background(Color.debug)
//    }
//
//    private var controls: some View {
//        VStack(spacing: 0) {
//            TimelineView(duration: playerControls.durationBinding, current: playerControls.currentTimeBinding)
//                .foregroundColor(.secondary)
//
//            Button(action: {
//                    model.togglePlayer()
//            }) {
//                HStack(spacing: 8) {
//                    authorAvatar
//
//                    VStack(alignment: .leading, spacing: 5) {
//                        Text(model.currentVideo?.title ?? "Not playing")
//                            .font(.headline)
//                            .foregroundColor(model.currentVideo.isNil ? .secondary : .accentColor)
//                            .lineLimit(1)
//
//                        Text(model.currentVideo?.author ?? "")
//                            .font(.subheadline)
//                            .foregroundColor(.secondary)
//                            .lineLimit(1)
//                    }
//
//                    Spacer()
//
//                    HStack {
//                        Group {
//                            if !model.currentItem.isNil {
//                                Button {
//                                    model.closeCurrentItem()
//                                    model.closePiP()
//                                } label: {
//                                    Label("Close Video", systemImage: "xmark")
//                                        .padding(.horizontal, 4)
//                                        .contentShape(Rectangle())
//                                }
//                            }
//
//                            if playerControls.isPlaying {
//                                Button(action: {
//                                    model.pause()
//                                }) {
//                                    Label("Pause", systemImage: "pause.fill")
//                                        .padding(.horizontal, 4)
//                                        .contentShape(Rectangle())
//                                }
//                            } else {
//                                Button(action: {
//                                    model.play()
//                                }) {
//                                    Label("Play", systemImage: "play.fill")
//                                        .padding(.horizontal, 4)
//                                        .contentShape(Rectangle())
//                                }
//                            }
//                        }
//                        .disabled(playerControls.isLoadingVideo || model.currentItem.isNil)
//                        .font(.system(size: 30))
//                        .frame(minWidth: 30)
//
//                        Button(action: { model.advanceToNextItem() }) {
//                            Label("Next", systemImage: "forward.fill")
//                                .padding(.vertical)
//                                .contentShape(Rectangle())
//                        }
//                        .disabled(model.queue.isEmpty)
//                    }
//                }
//                .buttonStyle(.plain)
//                .contentShape(Rectangle())
//            }
//        }
//        .buttonStyle(.plain)
//        .labelStyle(.iconOnly)
//        .padding(.horizontal)
//        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: barHeight)
//        .borderTop(height: 0.4, color: Color("ControlsBorderColor"))
//        .borderBottom(height: navigationStyle == .sidebar ? 0 : 0.4, color: Color("ControlsBorderColor"))
//    }
//
//    private var authorAvatar: some View {
//        Group {
//            if let video = model.currentItem?.video, let url = video.channel.thumbnailURL {
//                WebImage(url: url)
//                    .resizable()
//                    .placeholder {
//                        Rectangle().fill(Color("PlaceholderColor"))
//                    }
//                    .retryOnAppear(true)
//                    .indicator(.activity)
//                    .clipShape(Circle())
//                    .frame(width: 44, height: 44, alignment: .leading)
//            }
//        }
//    }
//
//    private var progressViewValue: Double {
//        [model.time?.seconds, model.videoDuration].compactMap { $0 }.min() ?? 0
//    }
//
//    private var progressViewTotal: Double {
//        model.videoDuration ?? 100
//    }
// }
//
struct PlayerControlsView_Previews: PreviewProvider {
    static var previews: some View {
        BrowserPlayerControls(context: .player) {
            BrowserPlayerControls {
                VStack {
                    Spacer()
                    Text("Hello")
                    Spacer()
                }
            }
            .offset(y: -100)
        }
        .injectFixtureEnvironmentObjects()
    }
}
