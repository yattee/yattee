import Siesta
import SwiftUI

struct TrendingView: View {
    @State private var category: TrendingCategory = .default
    @State private var country: Country! = .pl
    @State private var selectingCountry = false

    @ObservedObject private var store = Store<[Video]>()

    var resource: Resource {
        InvidiousAPI.shared.trending(category: category, country: country)
    }

    init() {
        resource.addObserver(store)
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

    var body: some View {
        Section {
            VStack(alignment: .center, spacing: 2) {
                #if os(tvOS)
                    toolbar
                        .scaleEffect(0.85)
                #endif

                VideosView(videos: store.collection)

                #if os(iOS)
                    toolbar
                        .font(.system(size: 14))
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .overlay(Divider().offset(x: 0, y: -2), alignment: .topTrailing)
                        .transaction { t in t.animation = .none }
                #endif
            }
        }
        #if os(tvOS)
            .fullScreenCover(isPresented: $selectingCountry, onDismiss: { setCountry(country) }) {
                TrendingCountry(selectedCountry: $country)
            }
        #else
            .sheet(isPresented: $selectingCountry, onDismiss: { setCountry(country) }) {
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
        #endif

        .onAppear {
            resource.loadIfNeeded()
        }
    }

    var categoryButton: some View {
        #if os(tvOS)
            Button(category.name) {
                setCategory(category.next())
            }
            .contextMenu {
                ForEach(TrendingCategory.allCases) { category in
                    Button(category.name) { setCategory(category) }
                }
            }
        #else
            Menu(category.name) {
                ForEach(TrendingCategory.allCases) { category in
                    Button(action: { setCategory(category) }) {
                        if category == self.category {
                            Label(category.name, systemImage: "checkmark")
                        } else {
                            Text(category.name)
                        }
                    }
                }
            }
        #endif
    }

    var countryButton: some View {
        Button(action: {
            selectingCountry.toggle()
            resource.removeObservers(ownedBy: store)
        }) {
            Text("\(country.flag) \(country.id)")
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

struct TrendingView_Previews: PreviewProvider {
    static var previews: some View {
        TrendingView()
            .environmentObject(NavigationState())
    }
}
