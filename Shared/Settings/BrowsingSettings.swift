import Defaults
import SwiftUI

struct BrowsingSettings: View {
    #if !os(tvOS)
        @Default(.accountPickerDisplaysUsername) private var accountPickerDisplaysUsername
        @Default(.roundedThumbnails) private var roundedThumbnails
    #endif
    @Default(.accountPickerDisplaysAnonymousAccounts) private var accountPickerDisplaysAnonymousAccounts
    #if os(iOS)
        @Default(.homeRecentDocumentsItems) private var homeRecentDocumentsItems
        @Default(.lockPortraitWhenBrowsing) private var lockPortraitWhenBrowsing
    #endif
    @Default(.thumbnailsQuality) private var thumbnailsQuality
    @Default(.channelOnThumbnail) private var channelOnThumbnail
    @Default(.timeOnThumbnail) private var timeOnThumbnail
    @Default(.showHome) private var showHome
    @Default(.showDocuments) private var showDocuments
    @Default(.showFavoritesInHome) private var showFavoritesInHome
    @Default(.showOpenActionsInHome) private var showOpenActionsInHome
    @Default(.showOpenActionsToolbarItem) private var showOpenActionsToolbarItem
    @Default(.homeHistoryItems) private var homeHistoryItems
    @Default(.visibleSections) private var visibleSections

    @EnvironmentObject<AccountsModel> private var accounts

    @State private var homeHistoryItemsText = ""
    #if os(iOS)
        @State private var homeRecentDocumentsItemsText = ""
    #endif
    #if os(macOS)
        @State private var presentingEditFavoritesSheet = false
    #endif

    var body: some View {
        Group {
            #if os(macOS)
                VStack(alignment: .leading) {
                    sections
                    Spacer()
                }
            #else
                List {
                    sections
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #endif
            #endif
        }
        #if os(tvOS)
        .frame(maxWidth: 1000)
        #else
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        #endif
        .navigationTitle("Browsing")
    }

    private var sections: some View {
        Group {
            homeSettings
            interfaceSettings
            if !accounts.isEmpty {
                thumbnailsSettings
                visibleSectionsSettings
            }
        }
    }

    private var homeSettings: some View {
        Section(header: SettingsHeader(text: "Home".localized())) {
            #if !os(tvOS)
                if !accounts.isEmpty {
                    Toggle("Show Home", isOn: $showHome)
                }
            #endif
            Toggle("Show Open Videos quick actions", isOn: $showOpenActionsInHome)
            HStack {
                Text("Recent history")
                TextField("Recent history", text: $homeHistoryItemsText)
                    .labelsHidden()
                #if !os(macOS)
                    .keyboardType(.numberPad)
                #endif
                    .onAppear {
                        homeHistoryItemsText = String(homeHistoryItems)
                    }
                    .onChange(of: homeHistoryItemsText) { newValue in
                        homeHistoryItems = Int(newValue) ?? 10
                    }
            }
            .multilineTextAlignment(.trailing)

            HStack {
                Text("Recent documents")
                TextField("Recent documents", text: $homeRecentDocumentsItemsText)
                    .labelsHidden()
                #if !os(macOS)
                    .keyboardType(.numberPad)
                #endif
                    .onAppear {
                        homeRecentDocumentsItemsText = String(homeRecentDocumentsItems)
                    }
                    .onChange(of: homeRecentDocumentsItemsText) { newValue in
                        homeRecentDocumentsItems = Int(newValue) ?? 3
                    }
            }
            .multilineTextAlignment(.trailing)

            if !accounts.isEmpty {
                Toggle("Show Favorites", isOn: $showFavoritesInHome)

                Group {
                    #if os(macOS)
                        Button {
                            presentingEditFavoritesSheet = true
                        } label: {
                            Text("Edit Favorites...")
                        }
                        .sheet(isPresented: $presentingEditFavoritesSheet) {
                            VStack(alignment: .leading) {
                                Button("Done") {
                                    presentingEditFavoritesSheet = false
                                }
                                .padding()
                                .keyboardShortcut(.cancelAction)

                                EditFavorites()
                            }
                            .frame(width: 500, height: 300)
                        }
                    #else
                        NavigationLink(destination: LazyView(EditFavorites())) {
                            Text("Edit Favorites...")
                        }
                    #endif
                }
                .disabled(!showFavoritesInHome)
            }
        }
    }

    private var interfaceSettings: some View {
        Section(header: SettingsHeader(text: "Interface".localized())) {
            #if !os(tvOS)
                Toggle("Show Open Videos toolbar button", isOn: $showOpenActionsToolbarItem)
            #endif
            #if os(iOS)
                Toggle("Show Documents", isOn: $showDocuments)

                Toggle("Lock portrait mode", isOn: $lockPortraitWhenBrowsing)
                    .onChange(of: lockPortraitWhenBrowsing) { lock in
                        if lock {
                            Orientation.lockOrientation(.portrait, andRotateTo: .portrait)
                        } else {
                            Orientation.lockOrientation(.allButUpsideDown)
                        }
                    }
            #endif

            if !accounts.isEmpty {
                #if !os(tvOS)
                    Toggle("Show account username", isOn: $accountPickerDisplaysUsername)
                #endif

                Toggle("Show anonymous accounts", isOn: $accountPickerDisplaysAnonymousAccounts)
            }
        }
    }

    private var thumbnailsSettings: some View {
        Section(header: SettingsHeader(text: "Thumbnails".localized())) {
            thumbnailsQualityPicker
            #if !os(tvOS)
                Toggle("Round corners", isOn: $roundedThumbnails)
            #endif
            Toggle("Show channel name", isOn: $channelOnThumbnail)
            Toggle("Show video length", isOn: $timeOnThumbnail)
        }
    }

    private var thumbnailsQualityPicker: some View {
        Picker("Quality", selection: $thumbnailsQuality) {
            ForEach(ThumbnailsQuality.allCases, id: \.self) { quality in
                Text(quality.description)
            }
        }
        .modifier(SettingsPickerModifier())
    }

    private var visibleSectionsSettings: some View {
        Section(header: SettingsHeader(text: "Sections".localized())) {
            #if os(macOS)
                let list = ForEach(VisibleSection.allCases, id: \.self) { section in
                    MultiselectRow(
                        title: section.title,
                        selected: visibleSections.contains(section)
                    ) { value in
                        toggleSection(section, value: value)
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

                    Spacer()
                }
            #else
                ForEach(VisibleSection.allCases, id: \.self) { section in
                    MultiselectRow(
                        title: section.title,
                        selected: visibleSections.contains(section)
                    ) { value in
                        toggleSection(section, value: value)
                    }
                }
            #endif
        }
    }

    private func toggleSection(_ section: VisibleSection, value: Bool) {
        if value {
            visibleSections.insert(section)
        } else {
            visibleSections.remove(section)
        }
    }
}

struct BrowsingSettings_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            BrowsingSettings()
        }
        .injectFixtureEnvironmentObjects()
    }
}
