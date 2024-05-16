import Foundation

enum SeekType: Equatable {
    case chapterSkip(String)
    case segmentSkip(String)
    case segmentRestore
    case userInteracted
    case loopRestart
    case backendSync

    var presentable: Bool {
        self != .backendSync
    }
}
