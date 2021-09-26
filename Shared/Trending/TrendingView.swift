import Defaults
import Siesta
import SwiftUI

struct TrendingView: View {
    @StateObject private var store = Store<[Video]>()

    @Default(.trendingCategory) private var category
    @Default(.trendingCountry) private var country

    @State private var presentingCountrySelection = false

    @EnvironmentObject<InvidiousAPI> private var api

    var resource: Resource {
        let resource = api.trending(category: category, country: country)
        resource.addObserver(store)

        return resource
    }

    var body: some View {
        Section {
            VStack(alignment: .center, spacing: 2) {
                #if os(tvOS)
                    toolbar
                        .scaleEffect(0.85)
                #endif

                if store.collection.isEmpty {
                    Text("Loading")
                }

                VideosView(videos: store.collection)
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
        #if os(macOS)
            .toolbar {
                ToolbarItemGroup {
                    categoryButton
                    countryButton
                }
            }
        #elseif os(iOS)
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Group {
                        HStack {
                            Text("Category")
                                .foregroundColor(.secondary)

                            categoryButton
                                // only way to disable Menu animation is to
                                // force redraw of the view when it changes
                                .id(UUID())
                        }

                        HStack {
                            Text("Country")
                                .foregroundColor(.secondary)

                            countryButton
                        }
                    }
                }
            }
        #endif
        .onChange(of: resource) { resource in
            resource.load()
        }
        .onAppear {
            resource.addObserver(store)
            resource.loadIfNeeded()
        }
    }

    var toolbar: some View {
        HStack {
            HStack {
                Text("Category")
                    .foregroundColor(.secondary)

                categoryButton
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
        TrendingView()
            .environmentObject(NavigationModel())
    }
}
