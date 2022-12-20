import SwiftUI

struct ControlsGradientView: View {
    @ObservedObject private var controls = PlayerControlsModel.shared

    var body: some View {
        if controls.presentingControls {
            Rectangle()
                .fill(
                    LinearGradient(stops: gradientStops, startPoint: .top, endPoint: .bottom)
                )
                .transition(.opacity)
        }
    }

    var gradientStops: [Gradient.Stop] {
        [
            Gradient.Stop(color: .black.opacity(0.3), location: 0.0),
            Gradient.Stop(color: .clear, location: 0.33),
            Gradient.Stop(color: .clear, location: 0.66),
            Gradient.Stop(color: .black.opacity(0.3), location: 1)
        ]
    }
}

struct ControlsGradientView_Previews: PreviewProvider {
    static var previews: some View {
        ControlsGradientView()
    }
}
