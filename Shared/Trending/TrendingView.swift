import Defaults
import Siesta
import SwiftUI

struct TrendingView: View {
    @StateObject private var store = Store<[Video]>()
    private var videos = [Video]()

    @Default(.trendingCategory) private var category
    @Default(.trendingCountry) private var country

    @Default(.trendingListingStyle) private var trendingListingStyle
    @Default(.hideShorts) private var hideShorts

    @State private var presentingCountrySelection = false

    @State private var favoriteItem: FavoriteItem?

    @ObservedObject private var accounts = AccountsModel.shared

    var trending: [ContentItem] {
        ContentItem.array(of: store.collection)
    }

    @State private var error: RequestError?

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
        Section {
            VStack(spacing: 0) {
                #if os(tvOS)
                    toolbar
                    HorizontalCells(items: trending)
                        .padding(.top, 40)

                    Spacer()
                #else
                    VerticalCells(items: trending)
                        .environment(\.scrollViewBottomPadding, 70)
                #endif
            }
            .environment(\.listingStyle, trendingListingStyle)
            .environment(\.hideShorts, hideShorts)
        }

        .toolbar {
            ToolbarItem {
                RequestErrorButton(error: error)
            }
            #if os(macOS)
                ToolbarItemGroup {
                    if let favoriteItem {
                        FavoriteButton(item: favoriteItem)
                            .id(favoriteItem.id)
                    }

                    if accounts.app.supportsTrendingCategories {
                        categoryButton
                    }
                    countryButton
                }
            #endif
        }
        .onChange(of: resource) { _ in
            resource.load()
                .onFailure { self.error = $0 }
                .onSuccess { _ in self.error = nil }
            updateFavoriteItem()
        }
        .onAppear {
            resource.loadIfNeeded()?
                .onFailure { self.error = $0 }
                .onSuccess { _ in self.error = nil }

            updateFavoriteItem()
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
                .background(
                    Button("Refresh") {
                        resource.load()
                            .onFailure { self.error = $0 }
                            .onSuccess { _ in self.error = nil }
                    }
                    .keyboardShortcut("r")
                    .opacity(0)
                )
                .navigationTitle("Trending")
        #endif
        #if os(iOS)
        .refreshControl { refreshControl in
            resource.load().onCompletion { _ in
                refreshControl.endRefreshing()
            }
        }
        .backport
        .refreshable {
            DispatchQueue.main.async {
                resource.load()
                    .onFailure { self.error = $0 }
                    .onSuccess { _ in self.error = nil }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                trendingMenu
            }
        }
        #endif
        #if os(macOS)
        .toolbar {
            ToolbarItem {
                ListingStyleButtons(listingStyle: $trendingListingStyle)
            }

            ToolbarItem {
                HideShortsButtons(hide: $hideShorts)
            }
        }
        #else
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    resource.loadIfNeeded()?
                        .onFailure { self.error = $0 }
                        .onSuccess { _ in self.error = nil }
                }
        #endif
    }

    #if os(tvOS)
        private var toolbar: some View {
            HStack {
                if accounts.app.supportsTrendingCategories {
                    HStack {
                        Text("Category")
                            .foregroundColor(.secondary)

                        categoryButton
                    }
                }

                HStack {
                    Text("Country")
                        .foregroundColor(.secondary)

                    countryButton
                }

                if let favoriteItem {
                    FavoriteButton(item: favoriteItem)
                        .id(favoriteItem.id)
                        .labelStyle(.iconOnly)
                }
            }
        }
    #endif

    #if os(iOS)
        var trendingMenu: some View {
            Menu {
                countryButton

                if accounts.app.supportsTrendingCategories {
                    categoryButton
                }

                ListingStyleButtons(listingStyle: $trendingListingStyle)

                Section {
                    HideShortsButtons(hide: $hideShorts)
                }

                Section {
                    SettingsButtons()
                }
            } label: {
                HStack(spacing: 12) {
                    Text("\(country.flag) \(country.name)")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Image(systemName: "chevron.down.circle.fill")
                        .foregroundColor(.accentColor)
                        .imageScale(.small)
                }
                .frame(maxWidth: 320)
            }
        }
    #endif

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
            Picker(category.controlLabel, selection: $category) {
                ForEach(TrendingCategory.allCases) { category in
                    Label(category.controlLabel, systemImage: category.systemImage).tag(category)
                }
            }
        #endif
    }

    private var countryButton: some View {
        Button(action: {
            presentingCountrySelection.toggle()
            resource.removeObservers(ownedBy: store)
        }) {
            #if os(iOS)
                Label("Country", systemImage: "flag")
            #else
                Text("\(country.flag) \(country.id)")

            #endif
        }
    }

    private func updateFavoriteItem() {
        favoriteItem = FavoriteItem(section: .trending(country.rawValue, category.rawValue))
    }
}

struct TrendingView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            TrendingView(Video.allFixtures)
        }
    }
}
