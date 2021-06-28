import SwiftUI

struct TrendingCountrySelectionView: View {
    @State private var query: String = ""

    @ObservedObject private var store = Store<[Country]>()
    @Binding var selectedCountry: Country

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(.vertical) {
            ForEach(store.collection) { country in
                Button(country.name) {
                    selectedCountry = country
                    dismiss()
                }
            }
            .frame(width: 800)
        }
        .searchable(text: $query, prompt: Text("Country name or two letter code"))
        .onChange(of: query) { newQuery in
            store.replace(Country.search(newQuery))
        }
        .background(.thinMaterial)
    }
}
