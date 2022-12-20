import SwiftUI

struct PlayingIndicatorView: View {
    var video: Video?
    var height = 65.0

    @State private var drawingHeight = true

    @ObservedObject private var player = PlayerModel.shared

    var body: some View {
        if player.isPlaying && player.currentVideo == video {
            HStack(spacing: 2) {
                bar(low: 0.4)
                    .animation(animation.speed(1.5), value: drawingHeight)
                bar(low: 0.3)
                    .animation(animation.speed(1.2), value: drawingHeight)
                bar(low: 0.5)
                    .animation(animation.speed(1.0), value: drawingHeight)
            }
            .opacity(player.currentVideo == video && player.isPlaying ? 1 : 0)
            .onAppear {
                drawingHeight.toggle()
            }
        }
    }

    func bar(low: Double = 0.0, high: Double = 1.0) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .foregroundColor(.white)
            .frame(height: (drawingHeight ? high : low) * height)
            .frame(height: height, alignment: .bottom)
            .shadow(radius: 3)
    }

    var animation: Animation {
        .easeIn(duration: 0.5).repeatForever()
    }
}

struct PlayingIndicatorView_Previews: PreviewProvider {
    static var previews: some View {
        PlayingIndicatorView(video: .fixture)
    }
}
