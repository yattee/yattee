import CoreMedia
import Foundation

final class PlaybackState: ObservableObject {
    @Published var live = false
    @Published var stream: Stream?
    @Published var time: CMTime?

    var aspectRatio: CGFloat? {
        let tracks = stream?.videoAsset.tracks(withMediaType: .video)

        guard tracks != nil else {
            return nil
        }

        let size: CGSize! = tracks!.first.flatMap {
            tracks!.isEmpty ? nil : $0.naturalSize.applying($0.preferredTransform)
        }

        guard size != nil else {
            return nil
        }

        return size.width / size.height
    }

    func reset() {
        stream = nil
        time = nil
    }
}
