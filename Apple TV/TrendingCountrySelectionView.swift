import SwiftUI

struct TrendingCountrySelectionView: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject private var provider = TrendingCountriesProvider()

    @State private var query: String = ""
    @Binding var selectedCountry: Country

    var body: some View {
        ZStack {
            VisualEffectView(effect: UIBlurEffect(style: .dark))

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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .edgesIgnoringSafeArea(.all)
    }

    var countries: [Country] {
        provider.load(query)

        return provider.countries
    }
}
