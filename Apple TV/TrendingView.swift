import Siesta
import SwiftUI

struct TrendingView: View {
    @State private var category: TrendingCategory = .default
    @State private var country: Country = .pl
    @State private var selectingCountry = false

    @ObservedObject private var store = Store<[Video]>()

    var resource: Resource {
        InvidiousAPI.shared.trending(category: category, country: country)
    }

    init() {
        resource.addObserver(store)
    }

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

                VideosView(videos: store.collection)
            }
        }.onAppear {
            resource.loadIfNeeded()
        }
    }

    var categoryButton: some View {
        Button(category.name) {
            setCategory(category.next())
        }
        .contextMenu {
            ForEach(TrendingCategory.allCases) { category in
                Button(category.name) { setCategory(category) }
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
            resource.removeObservers(ownedBy: store)
        }
        .fullScreenCover(isPresented: $selectingCountry, onDismiss: { setCountry(country) }) {
            TrendingCountrySelectionView(selectedCountry: $country)
        }
    }

    fileprivate func setCategory(_ category: TrendingCategory) {
        resource.removeObservers(ownedBy: store)
        self.category = category
        resource.addObserver(store)
        resource.loadIfNeeded()
    }

    fileprivate func setCountry(_ country: Country) {
        self.country = country
        resource.addObserver(store)
        resource.loadIfNeeded()
    }
}
