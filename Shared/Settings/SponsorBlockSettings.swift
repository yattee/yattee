import Defaults
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

struct SponsorBlockSettings: View {
    @ObservedObject private var settings = SettingsModel.shared

    @Default(.sponsorBlockInstance) private var sponsorBlockInstance
    @Default(.sponsorBlockCategories) private var sponsorBlockCategories
    @Default(.sponsorBlockColors) private var sponsorBlockColors
    @Default(.sponsorBlockShowTimeWithSkipsRemoved) private var showTimeWithSkipsRemoved
    @Default(.sponsorBlockShowCategoriesInTimeline) private var showCategoriesInTimeline
    @Default(.sponsorBlockShowNoticeAfterSkip) private var showNoticeAfterSkip

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
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                #endif
            }

            Section(header: Text("Playback")) {
                Toggle("Categories in timeline", isOn: $showCategoriesInTimeline)
                Toggle("Post-skip notice", isOn: $showNoticeAfterSkip)
                Toggle("Adjusted total time", isOn: $showTimeWithSkipsRemoved)
            }

            Section(header: SettingsHeader(text: "Categories to Skip".localized())) {
                categoryRows
            }

            #if os(iOS)
                colorSection

                Button {
                    settings.presentAlert(
                        Alert(
                            title: Text("Restore Default Colors?"),
                            message: Text("This action will reset all custom colors back to their original defaults. " +
                                "Any custom color changes you've made will be lost."),
                            primaryButton: .destructive(Text("Restore")) {
                                resetColors()
                            },
                            secondaryButton: .cancel()
                        )
                    )
                } label: {
                    Text("Restore Default Colors…")
                        .foregroundColor(.red)
                }
            #endif

            Section(footer: categoriesDetails) {
                EmptyView()
            }
        }
    }

    #if os(iOS)
        private var colorSection: some View {
            Section(header: SettingsHeader(text: "Colors for Categories")) {
                ForEach(SponsorBlockAPI.categories, id: \.self) { category in
                    LazyVStack(alignment: .leading) {
                        ColorPicker(
                            SponsorBlockAPI.categoryDescription(category) ?? "Unknown",
                            selection: Binding(
                                get: { getColor(for: category) },
                                set: { setColor($0, for: category) }
                            )
                        )
                    }
                }
            }
        }
    #endif

    private var categoryRows: some View {
        ForEach(SponsorBlockAPI.categories, id: \.self) { category in
            LazyVStack(alignment: .leading) {
                MultiselectRow(
                    title: SponsorBlockAPI.categoryDescription(category) ?? "Unknown",
                    selected: sponsorBlockCategories.contains(category)
                ) { value in
                    toggleCategory(category, value: value)
                }
            }
        }
    }

    private var categoriesDetails: some View {
        VStack(alignment: .leading) {
            ForEach(SponsorBlockAPI.categories, id: \.self) { category in
                Text(SponsorBlockAPI.categoryDescription(category) ?? "Category")
                    .fontWeight(.bold)
                    .padding(.bottom, 0.5)
                #if os(tvOS)
                    .focusable()
                #endif

                Text(SponsorBlockAPI.categoryDetails(category) ?? "Details")
                    .padding(.bottom, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundColor(.secondary)
    }

    func toggleCategory(_ category: String, value: Bool) {
        if let index = sponsorBlockCategories.firstIndex(where: { $0 == category }), !value {
            sponsorBlockCategories.remove(at: index)
        } else if value {
            sponsorBlockCategories.insert(category)
        }
    }

    private func getColor(for category: String) -> Color {
        if let hexString = sponsorBlockColors[category], let rgbValue = Int(hexString.dropFirst(), radix: 16) {
            let r = Double((rgbValue >> 16) & 0xFF) / 255.0
            let g = Double((rgbValue >> 8) & 0xFF) / 255.0
            let b = Double(rgbValue & 0xFF) / 255.0
            return Color(red: r, green: g, blue: b)
        }
        return Color("AppRedColor") // Fallback color if no match found
    }

    #if canImport(UIKit)
        private func setColor(_ color: Color, for category: String) {
            let uiColor = UIColor(color)

            // swiftlint:disable no_cgfloat
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            // swiftlint:enable no_cgfloat

            uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

            let r = Int(red * 255.0)
            let g = Int(green * 255.0)
            let b = Int(blue * 255.0)

            let rgbValue = (r << 16) | (g << 8) | b
            sponsorBlockColors[category] = String(format: "#%06x", rgbValue)
        }
    #endif

    private func resetColors() {
        sponsorBlockColors = SponsorBlockColors.dictionary
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
