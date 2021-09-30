import Defaults
import SwiftUI

struct VideosCellsVertical: View {
    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    var videos = [Video]()

    var body: some View {
        ScrollView(.vertical, showsIndicators: scrollViewShowsIndicators) {
            LazyVGrid(columns: items, alignment: .center) {
                ForEach(videos) { video in
                    VideoView(video: video)
                    #if os(tvOS)
                        .padding(.horizontal)
                    #endif
                }
            }
            .padding()
        }
        .id(UUID())
        #if os(tvOS)
            .padding(.horizontal, 10)
        #endif
        .edgesIgnoringSafeArea(.horizontal)
        #if os(macOS)
            .background()
            .frame(minWidth: 360)
        #endif
    }

    var items: [GridItem] {
        #if os(tvOS)
            videos.count < 3 ? Array(repeating: GridItem(.fixed(540)), count: [videos.count, 1].max()!) : adaptiveItem
        #else
            adaptiveItem
        #endif
    }

    var adaptiveItem: [GridItem] {
        [GridItem(.adaptive(minimum: adaptiveGridItemMinimumSize))]
    }

    var adaptiveGridItemMinimumSize: Double {
        #if os(iOS)
            return verticalSizeClass == .regular ? 320 : 800
        #elseif os(tvOS)
            return 540
        #else
            return 320
        #endif
    }

    var scrollViewShowsIndicators: Bool {
        #if !os(tvOS)
            true
        #else
            false
        #endif
    }
}

struct VideoCellsVertical_Previews: PreviewProvider {
    static var previews: some View {
        VideosCellsVertical(videos: Video.allFixtures)
            .injectFixtureEnvironmentObjects()
    }
}
