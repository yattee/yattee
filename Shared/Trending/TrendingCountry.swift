import SwiftUI

struct TrendingCountry: View {
    static let prompt = "Country Name or Code".localized()
    @Binding var selectedCountry: Country

    @StateObject private var store = Store(Country.allCases)

    @State private var query = ""
    @State private var selection: Country?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        VStack {
            #if !os(tvOS)
                HStack {
                    if #available(iOS 15.0, macOS 12.0, *) {
                        TextField("Country", text: $query, prompt: Text(Self.prompt))
                    } else {
                        TextField(Self.prompt, text: $query)
                    }

                    Button("Done") { selectCountryAndDismiss() }
                        .keyboardShortcut(.defaultAction)
                        .keyboardShortcut(.cancelAction)
                }
                .padding([.horizontal, .top])
            #endif
            countriesList
        }
        #if os(tvOS)
        .searchable(text: $query, placement: .automatic, prompt: Text(Self.prompt))
        .background(Color.background(scheme: colorScheme))
        #endif
    }

    var countriesList: some View {
        let list = ScrollViewReader { _ in
            List(store.collection, selection: $selection) { country in
                #if os(macOS)
                    Text(country.name)
                        .tag(country)
                        .id(country)
                #else
                    Button(country.name) { selectCountryAndDismiss(country) }
                #endif
            }
            .onChange(of: query) { newQuery in
                let results = Country.search(newQuery)
                store.replace(results)

                selection = results.first
            }
        }

        return Group {
            #if os(macOS)
                if #available(macOS 12.0, *) {
                    list
                        .listStyle(.inset(alternatesRowBackgrounds: true))
                } else {
                    list
                }
            #else
                list
            #endif
        }
        #if os(macOS)
        .padding(.bottom, 5)
        #endif
    }

    func selectCountryAndDismiss(_ country: Country? = nil) {
        if let selected = country ?? selection {
            selectedCountry = selected
        }

        presentationMode.wrappedValue.dismiss()
    }
}

struct TrendingCountry_Previews: PreviewProvider {
    static var previews: some View {
        TrendingCountry(selectedCountry: .constant(.pl))
    }
}
