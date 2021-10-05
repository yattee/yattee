import Foundation
import SwiftUI
struct PlayerControlsView<Content: View>: View {
    let content: Content

    @Environment(\.navigationStyle) private var navigationStyle
    @EnvironmentObject<PlayerModel> private var model
    @EnvironmentObject<NavigationModel> private var navigation

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
        HStack {
            Button(action: {
                model.presentingPlayer.toggle()
            }) {
                HStack {
                    if let item = model.currentItem {
                        HStack(spacing: 3) {
                            Text(item.video.title)
                                .fontWeight(.bold)
                                .foregroundColor(.accentColor)
                                .lineLimit(1)

                            Text("— \(item.video.author)")
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        Text("Not playing")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 20)
                .contentShape(Rectangle())
            }
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
                    .disabled(model.player.currentItem == nil)
                }
            }
            .frame(minWidth: 30)
            .scaleEffect(1.7)
            #if !os(tvOS)
                .keyboardShortcut("p")
            #endif

            Button(action: { model.advanceToNextItem() }) {
                Label("Next", systemImage: "forward.fill")
            }
            .disabled(model.queue.isEmpty)
        }
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
        .padding(.horizontal)
        .frame(minWidth: 0, maxWidth: .infinity)
        .padding(.vertical, 0)
        .background(.ultraThinMaterial)
        .borderTop(height: 0.4, color: Color("PlayerControlsBorderColor"))
        .borderBottom(height: navigationStyle == .sidebar ? 0 : 0.4, color: Color("PlayerControlsBorderColor"))
        #if !os(tvOS)
            .onSwipeGesture(up: {
                model.presentingPlayer = true
            })
        #endif
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
