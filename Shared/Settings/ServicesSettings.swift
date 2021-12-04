import Defaults
import SwiftUI

struct ServicesSettings: View {
    @Default(.sponsorBlockInstance) private var sponsorBlockInstance
    @Default(.sponsorBlockCategories) private var sponsorBlockCategories
    @Default(.commentsInstanceID) private var commentsInstanceID

    var body: some View {
        Section(header: SettingsHeader(text: "Comments")) {
            commentsInstancePicker
        }

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

        Section(header: SettingsHeader(text: "Categories to Skip")) {
            #if os(macOS)
                let list = ForEach(SponsorBlockAPI.categories, id: \.self) { category in
                    SponsorBlockCategorySelectionRow(
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
                    SponsorBlockCategorySelectionRow(
                        title: SponsorBlockAPI.categoryDescription(category) ?? "Unknown",
                        selected: sponsorBlockCategories.contains(category)
                    ) { value in
                        toggleCategory(category, value: value)
                    }
                }
            #endif
        }
    }

    private var commentsInstancePicker: some View {
        Picker("Comments", selection: $commentsInstanceID) {
            Text("Disabled").tag(String?.none)

            ForEach(InstancesModel.all.filter { $0.app.supportsComments }) { instance in
                Text(instance.description).tag(Optional(instance.id))
            }
        }
        .labelsHidden()
        #if os(iOS)
            .pickerStyle(.automatic)
        #elseif os(tvOS)
            .pickerStyle(.inline)
        #endif
    }

    func toggleCategory(_ category: String, value: Bool) {
        if let index = sponsorBlockCategories.firstIndex(where: { $0 == category }), !value {
            sponsorBlockCategories.remove(at: index)
        } else if value {
            sponsorBlockCategories.insert(category)
        }
    }

    struct SponsorBlockCategorySelectionRow: View {
        let title: String
        let selected: Bool
        var action: (Bool) -> Void

        @State private var toggleChecked = false

        var body: some View {
            Button(action: { action(!selected) }) {
                HStack {
                    #if os(macOS)
                        Toggle(isOn: $toggleChecked) {
                            Text(self.title)
                            Spacer()
                        }
                        .onAppear {
                            toggleChecked = selected
                        }
                        .onChange(of: toggleChecked) { new in
                            action(new)
                        }
                    #else
                        Text(self.title)
                        Spacer()
                        if selected {
                            Image(systemName: "checkmark")
                            #if os(iOS)
                                .foregroundColor(.accentColor)
                            #endif
                        }
                    #endif
                }
                .contentShape(Rectangle())
            }
            #if !os(tvOS)
            .buttonStyle(.plain)
            #endif
        }
    }
}

struct ServicesSettings_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ServicesSettings()
        }
    }
}
