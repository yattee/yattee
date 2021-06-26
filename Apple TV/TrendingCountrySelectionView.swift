import SwiftUI

struct TrendingCountrySelectionView: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject private var provider = TrendingCountriesProvider()

    @State private var query: String = ""
    @Binding var selectedCountry: Country

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(.vertical) {
            ForEach(countries) { country in
                Button(country.name) {
                    selectedCountry = country
                    presentationMode.wrappedValue.dismiss()
                }
            }
            .frame(width: 800)
        }
        .searchable(text: $query)
        .background(.thinMaterial)
    }

    var countries: [Country] {
        provider.load(query)

        return provider.countries
    }
}
