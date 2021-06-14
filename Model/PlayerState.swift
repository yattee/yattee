import AVFoundation
import Foundation

final class PlayerState: ObservableObject {
    @Published var currentStream: Stream!
    @Published var seekTo: CMTime?
}
