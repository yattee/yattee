import Defaults
import Siesta
import SwiftUI

struct TrendingView: View {
    @StateObject private var store = Store<[Video]>()
    private var videos = [Video]()

    @Default(.trendingCategory) private var category
    @Default(.trendingCountry) private var country

    @State private var presentingCountrySelection = false

    @EnvironmentObject<AccountsModel> private var accounts

    var popular: [ContentItem] {
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
                        HorizontalCells(items: popular)
                            .padding(.top, 40)

                        Spacer()
                    #else
                        VerticalCells(items: popular)
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
                    if accounts.app.supportsTrendingCategories {
                        categoryButton
                    }
                    countryButton
                }
            #elseif os(iOS)
                ToolbarItemGroup(placement: .bottomBar) {
                    Group {
                        if accounts.app.supportsTrendingCategories {
                            HStack {
                                Text("Category")
                                    .foregroundColor(.secondary)

                                categoryButton
                                    // only way to disable Menu animation is to
                                    // force redraw of the view when it changes
                                    .id(UUID())
                            }
                        } else {
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
        }
        .onAppear {
            if videos.isEmpty {
                resource.addObserver(store)
                resource.loadIfNeeded()
            } else {
                store.replace(videos)
            }
        }
    }

    var toolbar: some View {
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
        }
    }

    var categoryButton: some View {
        #if os(tvOS)
            Button(category.name) {
                self.category = category.next()
            }
            .contextMenu {
                ForEach(TrendingCategory.allCases) { category in
                    Button(category.name) { self.category = category }
                }

                Button("Cancel", role: .cancel) {}
            }

        #else
            Picker("Category", selection: $category) {
                ForEach(TrendingCategory.allCases) { category in
                    Text(category.name).tag(category)
                }
            }
        #endif
    }

    var countryButton: some View {
        Button(action: {
            presentingCountrySelection.toggle()
            resource.removeObservers(ownedBy: store)
        }) {
            Text("\(country.flag) \(country.id)")
        }
    }
}

struct TrendingView_Previews: PreviewProvider {
    static var previews: some View {
        TrendingView(Video.allFixtures)
            .injectFixtureEnvironmentObjects()
    }
}
