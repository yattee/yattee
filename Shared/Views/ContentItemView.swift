import Foundation
import SwiftUI

struct ContentItemView: View {
    let item: ContentItem

    var body: some View {
        Group {
            switch item.contentType {
            case .playlist:
                VideoCell(video: item.video)
            case .channel:
                ChannelCell(channel: item.channel)
            default:
                VideoCell(video: item.video)
            }
        }
    }
}
