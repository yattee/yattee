import Defaults
import SwiftUI

struct SponsorBlockSettings: View {
    @Default(.sponsorBlockInstance) private var sponsorBlockInstance
    @Default(.sponsorBlockCategories) private var sponsorBlockCategories

    var body: some View {
        Group {
            #if os(macOS)
                sections

                Spacer()
            #else
                List {
                    sections
                }
            #endif
        }
        #if os(tvOS)
        .frame(maxWidth: 1000)
        #else
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        #endif
        .navigationTitle("SponsorBlock")
    }

    private var sections: some View {
        Group {
            Section(header: SettingsHeader(text: "SponsorBlock API")) {
                TextField(
                    "SponsorBlock API Instance",
                    text: $sponsorBlockInstance
                )
                .labelsHidden()
                #if !os(macOS)
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                #endif
            }

            Section(header: SettingsHeader(text: "Categories to Skip".localized()), footer: categoriesDetails) {
                #if os(macOS)
                    let list = ForEach(SponsorBlockAPI.categories, id: \.self) { category in
                        MultiselectRow(
                            title: SponsorBlockAPI.categoryDescription(category) ?? "Unknown",
                            selected: sponsorBlockCategories.contains(category)
                        ) { value in
                            toggleCategory(category, value: value)
                        }
                    }

                    Group {
                        if #available(macOS 12.0, *) {
                            list
                                .listStyle(.inset(alternatesRowBackgrounds: true))
                        } else {
                            list
                                .listStyle(.inset)
                        }
                    }
                    Spacer()
                #else
                    ForEach(SponsorBlockAPI.categories, id: \.self) { category in
                        MultiselectRow(
                            title: SponsorBlockAPI.categoryDescription(category) ?? "Unknown",
                            selected: sponsorBlockCategories.contains(category)
                        ) { value in
                            toggleCategory(category, value: value)
                        }
                    }
                #endif
            }
        }
    }

    private var categoriesDetails: some View {
        VStack(alignment: .leading) {
            ForEach(SponsorBlockAPI.categories, id: \.self) { category in
                Text(SponsorBlockAPI.categoryDescription(category) ?? "Category")
                    .fontWeight(.bold)
                #if os(tvOS)
                    .focusable()
                #endif

                Text(SponsorBlockAPI.categoryDetails(category) ?? "Details")
                    .padding(.bottom, 3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundColor(.secondary)
        .padding(.top, 3)
    }

    func toggleCategory(_ category: String, value: Bool) {
        if let index = sponsorBlockCategories.firstIndex(where: { $0 == category }), !value {
            sponsorBlockCategories.remove(at: index)
        } else if value {
            sponsorBlockCategories.insert(category)
        }
    }
}

struct SponsorBlockSettings_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            SponsorBlockSettings()
        }
        .frame(maxHeight: 600)
    }
}
