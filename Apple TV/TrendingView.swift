import SwiftUI

struct TrendingView: View {
    @EnvironmentObject private var state: AppState

    @ObservedObject private var videosProvider = TrendingVideosProvider()

    @SceneStorage("category") var category: TrendingCategory = .default
    @SceneStorage("country") var country: Country = .pl

    @State private var selectingCountry = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    Spacer()

                    categoryButton
                    countryFlag
                    countryButton

                    Spacer()
                }
                .scaleEffect(0.85)

                VideosView(videos: videos)
            }
        }
    }

    var videos: [Video] {
        videosProvider.load(category: category, country: country)

        return videosProvider.videos
    }

    var categoryButton: some View {
        Button(category.name) {
            category = category.next()
        }
        .contextMenu {
            ForEach(TrendingCategory.allCases) { category in
                Button(category.name) {
                    self.category = category
                }
            }
        }
    }

    var countryFlag: some View {
        Text(country.flag)
            .font(.system(size: 60))
    }

    var countryButton: some View {
        Button(country.rawValue) {
            selectingCountry.toggle()
        }
        .fullScreenCover(isPresented: $selectingCountry) {
            TrendingCountrySelectionView(selectedCountry: $country)
        }
    }
}
