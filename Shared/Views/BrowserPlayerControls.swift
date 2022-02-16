import Foundation
import SwiftUI

struct BrowserPlayerControls<Content: View, Toolbar: View>: View {
    let content: Content
    let toolbar: Toolbar?

    @Environment(\.navigationStyle) private var navigationStyle
    @EnvironmentObject<PlayerControlsModel> private var playerControls
    @EnvironmentObject<PlayerModel> private var model

    init(@ViewBuilder toolbar: @escaping () -> Toolbar? = { nil }, @ViewBuilder content: @escaping () -> Content) {
        self.content = content()
        self.toolbar = toolbar()
    }

    init(@ViewBuilder content: @escaping () -> Content) where Toolbar == EmptyView {
        self.init(toolbar: { EmptyView() }, content: content)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            content
            #if !os(tvOS)
            .frame(minHeight: 0, maxHeight: .infinity)
            #endif

            Group {
                #if !os(tvOS)
                    #if !os(macOS)
                        toolbar
                            .frame(height: 100)
                            .offset(x: 0, y: -28)
                    #endif
                    controls

                #endif
            }
            .borderTop(height: 0.4, color: Color("ControlsBorderColor"))
            #if os(macOS)
                .background(VisualEffectBlur(material: .sidebar))
            #elseif os(iOS)
                .background(VisualEffectBlur(blurStyle: .systemThinMaterial).edgesIgnoringSafeArea(.all))
            #endif
        }
    }

    private var controls: some View {
        HStack {
            Button(action: {
                model.togglePlayer()
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.currentVideo?.title ?? "Not playing")
                            .font(.system(size: 14).bold())
                            .foregroundColor(model.currentItem.isNil ? .secondary : .accentColor)
                            .lineLimit(1)

                        if let video = model.currentVideo {
                            Text(video.author)
                                .fontWeight(.bold)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .contextMenu {
                        Button {
                            model.closeCurrentItem()
                        } label: {
                            Label("Close Video", systemImage: "xmark.circle")
                                .labelStyle(.automatic)
                        }
                        .disabled(model.currentItem.isNil)
                    }

                    Spacer()
                }
                .padding(.vertical)
                .contentShape(Rectangle())
            }
            .padding(.vertical, 20)

            ZStack(alignment: .bottom) {
                HStack {
                    Group {
                        if playerControls.isPlaying {
                            Button(action: {
                                model.pause()
                            }) {
                                Label("Pause", systemImage: "pause.fill")
                            }
                        } else {
                            Button(action: {
                                model.play()
                            }) {
                                Label("Play", systemImage: "play.fill")
                            }
                        }
                    }
                    .disabled(playerControls.isLoadingVideo)
                    .font(.system(size: 30))
                    .frame(minWidth: 30)

                    Button(action: { model.advanceToNextItem() }) {
                        Label("Next", systemImage: "forward.fill")
                            .padding(.vertical)
                            .contentShape(Rectangle())
                    }
                    .disabled(model.queue.isEmpty)
                }

                ProgressView(value: progressViewValue, total: progressViewTotal)
                    .progressViewStyle(.linear)
                #if os(iOS)
                    .frame(maxWidth: 60)
                #else
                    .offset(y: 6)
                    .frame(maxWidth: 70)
                #endif
            }
        }
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
        .padding(.horizontal)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: 55)
        .padding(.vertical, 0)
        .borderTop(height: 0.4, color: Color("ControlsBorderColor"))
        .borderBottom(height: navigationStyle == .sidebar ? 0 : 0.4, color: Color("ControlsBorderColor"))
        #if !os(tvOS)
            .onSwipeGesture(up: {
                model.show()
            })
        #endif
    }

    private var progressViewValue: Double {
        [model.time?.seconds, model.videoDuration].compactMap { $0 }.min() ?? 0
    }

    private var progressViewTotal: Double {
        model.videoDuration ?? 100
    }
}

struct PlayerControlsView_Previews: PreviewProvider {
    static var previews: some View {
        BrowserPlayerControls {
            VStack {
                Spacer()
                Text("Hello")
                Spacer()
            }
        }
        .injectFixtureEnvironmentObjects()
    }
}
