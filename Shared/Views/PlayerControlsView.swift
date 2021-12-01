import Foundation
import SwiftUI
struct PlayerControlsView<Content: View>: View {
    let content: Content

    @Environment(\.navigationStyle) private var navigationStyle
    @EnvironmentObject<PlayerModel> private var model

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            content
            #if !os(tvOS)
            .frame(minHeight: 0, maxHeight: .infinity)
            .padding(.bottom, 50)
            #endif

            #if !os(tvOS)
                controls
            #endif
        }
    }

    private var controls: some View {
        let controls = HStack {
            Button(action: {
                model.presentingPlayer.toggle()
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.currentItem?.video?.title ?? "Not playing")
                            .font(.system(size: 14).bold())
                            .foregroundColor(model.currentItem.isNil ? .secondary : .accentColor)
                            .lineLimit(1)

                        Text(model.currentItem?.video?.author ?? "Yattee v\(appVersion) (build \(appBuild))")
                            .fontWeight(model.currentItem.isNil ? .light : .bold)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .padding(.vertical, 20)

            ZStack(alignment: .bottom) {
                HStack {
                    Group {
                        if model.isPlaying {
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
                            .disabled(model.player.currentItem.isNil)
                        }
                    }
                    .font(.system(size: 30))
                    .frame(minWidth: 30)

                    Button(action: { model.advanceToNextItem() }) {
                        Label("Next", systemImage: "forward.fill")
                    }
                    .disabled(model.queue.isEmpty)
                }

                ProgressView(value: progressViewValue, total: progressViewTotal)
                    .progressViewStyle(.linear)
                #if os(iOS)
                    .offset(x: 0, y: 8)
                    .frame(maxWidth: 60)
                #else
                    .offset(x: 0, y: 15)
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
                model.presentingPlayer = true
            })
        #endif

        return Group {
            if #available(iOS 15.0, macOS 12.0, tvOS 15.0, *) {
                controls
                    .background(Material.ultraThinMaterial)
            } else {
                controls
                    .background(Color.tertiaryBackground)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }

    private var progressViewValue: Double {
        [model.time?.seconds, model.videoDuration].compactMap { $0 }.min() ?? 0
    }

    private var progressViewTotal: Double {
        model.playerItemDuration?.seconds ?? model.currentVideo?.length ?? progressViewValue
    }
}

struct PlayerControlsView_Previews: PreviewProvider {
    static var previews: some View {
        PlayerControlsView {
            VStack {
                Spacer()
                Text("Hello")
                Spacer()
            }
        }
        .injectFixtureEnvironmentObjects()
    }
}
