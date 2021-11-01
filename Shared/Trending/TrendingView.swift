import Defaults
import Siesta
import SwiftUI

struct TrendingView: View {
    @StateObject private var store = Store<[Video]>()
    private var videos = [Video]()

    @Default(.trendingCategory) private var category
    @Default(.trendingCountry) private var country

    @State private var presentingCountrySelection = false

    @State private var favoriteItem: FavoriteItem?

    @EnvironmentObject<AccountsModel> private var accounts

    var trending: [ContentItem] {
        ContentItem.array(of: store.collection)
    }

    init(_ videos: [Video] = [Video]()) {
        self.videos = videos
    }

    var resource: Resource {
        let newResource: Resource

        newResource = accounts.api.trending(country: country, category: category)
        newResource.addObserver(store)

        return newResource
    }

    var body: some View {
        PlayerControlsView {
            Section {
                VStack(alignment: .center, spacing: 0) {
                    #if os(tvOS)
                        toolbar
                        HorizontalCells(items: trending)
                            .padding(.top, 40)

                        Spacer()
                    #else
                        VerticalCells(items: trending)
                    #endif
                }
            }
        }
        #if os(tvOS)
            .fullScreenCover(isPresented: $presentingCountrySelection) {
                TrendingCountry(selectedCountry: $country)
            }
        #else
            .sheet(isPresented: $presentingCountrySelection) {
                TrendingCountry(selectedCountry: $country)
                #if os(macOS)
                    .frame(minWidth: 400, minHeight: 400)
                #endif
            }
            .navigationTitle("Trending")
        #endif
        .toolbar {
            #if os(macOS)
                ToolbarItemGroup {
                    if let favoriteItem = favoriteItem {
                        FavoriteButton(item: favoriteItem)
                            .id(favoriteItem.id)
                    }

                    if accounts.app.supportsTrendingCategories {
                        categoryButton
                    }
                    countryButton
                }
            #elseif os(iOS)
                ToolbarItemGroup(placement: .bottomBar) {
                    Group {
                        HStack {
                            if accounts.app.supportsTrendingCategories {
                                Text("Category")
                                    .foregroundColor(.secondary)

                                categoryButton
                                    // only way to disable Menu animation is to
                                    // force redraw of the view when it changes
                                    .id(UUID())
                            }
                        }

                        Spacer()

                        if let favoriteItem = favoriteItem {
                            FavoriteButton(item: favoriteItem)
                                .id(favoriteItem.id)

                            Spacer()
                        }

                        HStack {
                            Text("Country")
                                .foregroundColor(.secondary)

                            countryButton
                        }
                    }
                }
            #endif
        }
        .onChange(of: resource) { _ in
            resource.load()
            updateFavoriteItem()
        }
        .onAppear {
            if videos.isEmpty {
                resource.addObserver(store)
                resource.loadIfNeeded()
            } else {
                store.replace(videos)
            }

            updateFavoriteItem()
        }
    }

    private var toolbar: some View {
        HStack {
            if accounts.app.supportsTrendingCategories {
                HStack {
                    Text("Category")
                        .foregroundColor(.secondary)

                    categoryButton
                }
            }

            #if os(iOS)
                Spacer()
            #endif

            HStack {
                Text("Country")
                    .foregroundColor(.secondary)

                countryButton
            }

            #if os(tvOS)
                if let favoriteItem = favoriteItem {
                    FavoriteButton(item: favoriteItem)
                        .id(favoriteItem.id)
                        .labelStyle(.iconOnly)
                }
            #endif
        }
    }

    private var categoryButton: some View {
        #if os(tvOS)
            Button(category.name) {
                self.category = category.next()
            }
            .contextMenu {
                ForEach(TrendingCategory.allCases) { category in
                    Button(category.controlLabel) { self.category = category }
                }

                Button("Cancel", role: .cancel) {}
            }

        #else
            Picker("Category", selection: $category) {
                ForEach(TrendingCategory.allCases) { category in
                    Text(category.controlLabel).tag(category)
                }
            }
        #endif
    }

    private var countryButton: some View {
        Button(action: {
            presentingCountrySelection.toggle()
            resource.removeObservers(ownedBy: store)
        }) {
            Text("\(country.flag) \(country.id)")
        }
    }

    private func updateFavoriteItem() {
        favoriteItem = FavoriteItem(section: .trending(country.rawValue, category.rawValue))
    }
}

struct TrendingView_Previews: PreviewProvider {
    static var previews: some View {
        TrendingView(Video.allFixtures)
            .injectFixtureEnvironmentObjects()
    }
}
