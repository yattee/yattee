import Defaults
import SwiftUI

struct VideosCellsHorizontal: View {
    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    var videos = [Video]()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 20) {
                ForEach(videos) { video in
                    VideoView(video: video)
                        .environment(\.horizontalCells, true)
                    #if os(tvOS)
                        .frame(width: 580)
                        .padding(.trailing, 20)
                        .padding(.bottom, 40)
                    #else
                        .frame(width: 300)
                    #endif
                }
            }
            #if os(tvOS)
                .padding(.horizontal, 40)
                .padding(.vertical, 30)
            #else
                .padding(.horizontal, 15)
                .padding(.vertical, 20)
            #endif
        }
        .id(UUID())
        #if os(tvOS)
            .frame(height: 560)
        #else
            .frame(height: 280)
        #endif

        .edgesIgnoringSafeArea(.horizontal)
    }
}

struct VideoCellsHorizontal_Previews: PreviewProvider {
    static var previews: some View {
        VideosCellsHorizontal(videos: Video.allFixtures)
            .injectFixtureEnvironmentObjects()
    }
}
