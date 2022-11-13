import Foundation

struct VideoDetailsTool: Identifiable {
    var id: String {
        page.rawValue
    }

    var icon: String
    var name: String
    var toolPostion: CGRect = .zero
    var page = VideoDetails.DetailsPage.info

    func isAvailable(for video: Video?, sidebarQueue: Bool) -> Bool {
        guard !YatteeApp.isForPreviews else {
            return true
        }
        switch page {
        case .info:
            return video != nil && !video!.isLocal
        case .inspector:
            return true
        case .chapters:
            return video != nil && !video!.chapters.isEmpty
        case .comments:
            return video != nil && !video!.isLocal
        case .related:
            return !sidebarQueue && video != nil && !video!.isLocal
        case .queue:
            return !sidebarQueue
        }
    }
}
