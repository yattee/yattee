import Defaults
import SwiftUI

struct BrowsingSettings: View {
    #if !os(tvOS)
        @Default(.accountPickerDisplaysUsername) private var accountPickerDisplaysUsername
        @Default(.roundedThumbnails) private var roundedThumbnails
    #endif
    @Default(.accountPickerDisplaysAnonymousAccounts) private var accountPickerDisplaysAnonymousAccounts
    @Default(.showUnwatchedFeedBadges) private var showUnwatchedFeedBadges
    @Default(.keepChannelsWithUnwatchedFeedOnTop) private var keepChannelsWithUnwatchedFeedOnTop
    #if os(iOS)
        @Default(.enterFullscreenInLandscape) private var enterFullscreenInLandscape
        @Default(.lockPortraitWhenBrowsing) private var lockPortraitWhenBrowsing
        @Default(.showDocuments) private var showDocuments
    #endif
    @Default(.thumbnailsQuality) private var thumbnailsQuality
    @Default(.channelOnThumbnail) private var channelOnThumbnail
    @Default(.timeOnThumbnail) private var timeOnThumbnail
    @Default(.showOpenActionsToolbarItem) private var showOpenActionsToolbarItem
    @Default(.visibleSections) private var visibleSections
    @Default(.startupSection) private var startupSection
    @Default(.showSearchSuggestions) private var showSearchSuggestions
    @Default(.playerButtonSingleTapGesture) private var playerButtonSingleTapGesture
    @Default(.playerButtonDoubleTapGesture) private var playerButtonDoubleTapGesture
    @Default(.playerButtonShowsControlButtonsWhenMinimized) private var playerButtonShowsControlButtonsWhenMinimized
    @Default(.playerButtonIsExpanded) private var playerButtonIsExpanded
    @Default(.playerBarMaxWidth) private var playerBarMaxWidth
    @Default(.expandChannelDescription) private var expandChannelDescription
    @Default(.showChannelAvatarInChannelsLists) private var showChannelAvatarInChannelsLists
    @Default(.showChannelAvatarInVideosListing) private var showChannelAvatarInVideosListing

    @ObservedObject private var accounts = AccountsModel.shared

    #if os(iOS)
        @State private var homeRecentDocumentsItemsText = ""
    #endif
    #if os(macOS)
        @State private var presentingHomeSettingsSheet = false
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
        .frame(maxWidth: 1200)
        #else
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        #endif
        .navigationTitle("Browsing")
    }

    private var sections: some View {
        Group {
            homeSettings
            if !accounts.isEmpty {
                startupSectionPicker
                showSearchSuggestionsToggle
                visibleSectionsSettings
            }
            let interface = interfaceSettings
            #if os(tvOS)
                if !accounts.isEmpty {
                    interface
                }
            #else
                interface
                playerBarSettings
            #endif
            if !accounts.isEmpty {
                thumbnailsSettings
            }
        }
    }

    @ViewBuilder private var homeSettings: some View {
        if !accounts.isEmpty {
            Section {
                #if os(macOS)
                    Button {
                        presentingHomeSettingsSheet = true
                    } label: {
                        Text("Home Settings")
                    }
                    .sheet(isPresented: $presentingHomeSettingsSheet) {
                        VStack(alignment: .leading) {
                            Button("Done") {
                                presentingHomeSettingsSheet = false
                            }
                            .padding()
                            .keyboardShortcut(.cancelAction)

                            HomeSettings()
                        }
                        .frame(width: 500, height: 800)
                    }
                #else
                    NavigationLink(destination: LazyView(HomeSettings())) {
                        Text("Home Settings")
                    }
                #endif
            }
        }
    }

    #if !os(tvOS)
        private var playerBarSettings: some View {
            Section(header: SettingsHeader(text: "Player Bar".localized()), footer: playerBarFooter) {
                Toggle("Open expanded", isOn: $playerButtonIsExpanded)
                Toggle("Always show controls buttons", isOn: $playerButtonShowsControlButtonsWhenMinimized)
                playerBarGesturePicker("Single tap gesture".localized(), selection: $playerButtonSingleTapGesture)
                playerBarGesturePicker("Double tap gesture".localized(), selection: $playerButtonDoubleTapGesture)
                HStack {
                    Text("Maximum width expanded")
                    Spacer()
                    TextField("Maximum width expanded", text: $playerBarMaxWidth)
                        .frame(maxWidth: 100, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                        .labelsHidden()
                    #if !os(macOS)
                        .keyboardType(.numberPad)
                    #endif
                }
            }
        }

        func playerBarGesturePicker(_ label: String, selection: Binding<PlayerTapGestureAction>) -> some View {
            Picker(label, selection: selection) {
                ForEach(PlayerTapGestureAction.allCases, id: \.rawValue) { action in
                    Text(action.label.localized()).tag(action)
                }
            }
        }

        var playerBarFooter: some View {
            #if os(iOS)
                Text("Tap and hold channel thumbnail to open context menu with more actions")
            #elseif os(macOS)
                Text("Right click channel thumbnail to open context menu with more actions")
                    .foregroundColor(.secondary)
                    .padding(.bottom, 10)
            #endif
        }
    #endif

    private var interfaceSettings: some View {
        Section(header: SettingsHeader(text: "Interface".localized())) {
            #if !os(tvOS)
                Toggle("Show Open Videos toolbar button", isOn: $showOpenActionsToolbarItem)
            #endif
            #if os(iOS)
                Toggle("Show Documents", isOn: $showDocuments)

                if Constants.isIPad {
                    Toggle("Lock portrait mode", isOn: $lockPortraitWhenBrowsing)
                        .onChange(of: lockPortraitWhenBrowsing) { lock in
                            if lock {
                                enterFullscreenInLandscape = true
                                Orientation.lockOrientation(.portrait, andRotateTo: .portrait)
                            } else {
                                enterFullscreenInLandscape = false
                                Orientation.lockOrientation(.all)
                            }
                        }
                }
            #endif

            if !accounts.isEmpty {
                #if !os(tvOS)
                    Toggle("Show account username", isOn: $accountPickerDisplaysUsername)
                #endif

                Toggle("Show anonymous accounts", isOn: $accountPickerDisplaysAnonymousAccounts)
                Toggle("Show unwatched feed badges", isOn: $showUnwatchedFeedBadges)
                    .onChange(of: showUnwatchedFeedBadges) { newValue in
                        if newValue {
                            FeedModel.shared.calculateUnwatchedFeed()
                        }
                    }

                Toggle("Open channels with description expanded", isOn: $expandChannelDescription)
            }

            Toggle("Keep channels with unwatched videos on top of subscriptions list", isOn: $keepChannelsWithUnwatchedFeedOnTop)

            Toggle("Show channel avatars in channels lists", isOn: $showChannelAvatarInChannelsLists)
            Toggle("Show channel avatars in videos lists", isOn: $showChannelAvatarInVideosListing)
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
            ForEach(VisibleSection.allCases, id: \.self) { section in
                MultiselectRow(
                    title: section.title,
                    selected: visibleSections.contains(section)
                ) { value in
                    toggleSection(section, value: value)
                }
            }
        }
    }

    private var startupSectionPicker: some View {
        Group {
            #if os(tvOS)
                SettingsHeader(text: "Startup section".localized())
            #endif
            Picker("Startup section", selection: $startupSection) {
                ForEach(StartupSection.allCases, id: \.rawValue) { section in
                    Text(section.label).tag(section)
                }
            }
            .modifier(SettingsPickerModifier())
        }
    }

    private var showSearchSuggestionsToggle: some View {
        Toggle("Show search suggestions", isOn: $showSearchSuggestions)
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
