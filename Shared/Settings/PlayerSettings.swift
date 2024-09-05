import Defaults
import SwiftUI

struct PlayerSettings: View {
    @Default(.instances) private var instances
    @Default(.playerInstanceID) private var playerInstanceID

    @Default(.playerSidebar) private var playerSidebar

    @Default(.showKeywords) private var showKeywords
    @Default(.showComments) private var showComments
    #if !os(tvOS)
        @Default(.showScrollToTopInComments) private var showScrollToTopInComments
        @Default(.collapsedLinesDescription) private var collapsedLinesDescription
        @Default(.exitFullscreenOnEOF) private var exitFullscreenOnEOF
    #endif
    @Default(.expandVideoDescription) private var expandVideoDescription
    @Default(.pauseOnHidingPlayer) private var pauseOnHidingPlayer
    @Default(.closeVideoOnEOF) private var closeVideoOnEOF
    #if os(iOS)
        @Default(.enterFullscreenInLandscape) private var enterFullscreenInLandscape
        @Default(.lockPortraitWhenBrowsing) private var lockPortraitWhenBrowsing
        @Default(.rotateToLandscapeOnEnterFullScreen) private var rotateToLandscapeOnEnterFullScreen
    #endif
    @Default(.closePiPOnNavigation) private var closePiPOnNavigation
    @Default(.closePiPOnOpeningPlayer) private var closePiPOnOpeningPlayer
    @Default(.closePlayerOnOpeningPiP) private var closePlayerOnOpeningPiP
    #if !os(macOS)
        @Default(.pauseOnEnteringBackground) private var pauseOnEnteringBackground
        @Default(.closePiPAndOpenPlayerOnEnteringForeground) private var closePiPAndOpenPlayerOnEnteringForeground
    #endif

    @Default(.enableReturnYouTubeDislike) private var enableReturnYouTubeDislike

    @Default(.showRelated) private var showRelated
    @Default(.showInspector) private var showInspector

    @Default(.showChapters) private var showChapters
    @Default(.showChapterThumbnails) private var showThumbnails
    @Default(.showChapterThumbnailsOnlyWhenDifferent) private var showThumbnailsOnlyWhenDifferent
    @Default(.expandChapters) private var expandChapters

    @Default(.captionsAutoShow) private var captionsAutoShow
    @Default(.captionsDefaultLanguageCode) private var captionsDefaultLanguageCode
    @Default(.captionsFallbackLanguageCode) private var captionsFallbackLanguageCode
    @Default(.captionsFontScaleSize) private var captionsFontScaleSize
    @Default(.captionsFontColor) private var captionsFontColor

    @ObservedObject private var accounts = AccountsModel.shared

    #if os(iOS)
        private var idiom: UIUserInterfaceIdiom {
            UIDevice.current.userInterfaceIdiom
        }
    #endif

    #if os(tvOS)
        @State private var isShowingDefaultLanguagePicker = false
        @State private var isShowingFallbackLanguagePicker = false
    #endif

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
        #elseif os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Player")
    }

    private var sections: some View {
        Group {
            Section(header: SettingsHeader(text: "Playback".localized())) {
                if !accounts.isEmpty {
                    sourcePicker
                }
                pauseOnHidingPlayerToggle
                closeVideoOnEOFToggle
                #if os(macOS)
                    exitFullscreenOnEOFToggle
                #endif
                #if !os(macOS)
                    pauseOnEnteringBackgroundToogle
                #endif
            }

            #if !os(tvOS)
                Section(header: SettingsHeader(text: "Info".localized())) {
                    expandVideoDescriptionToggle
                    collapsedLineDescriptionStepper
                    showRelatedToggle
                    #if os(macOS)
                        HStack {
                            Text("Inspector")
                            inspectorVisibilityPicker
                        }
                        .padding(.leading, 20)
                    #else
                        inspectorVisibilityPicker
                    #endif
                }
            #endif

            Section(header: SettingsHeader(text: "Captions".localized())) {
                #if os(tvOS)
                    Text("Size").font(.subheadline)
                #endif
                captionsFontScaleSizePicker
                #if os(tvOS)
                    Text("Color").font(.subheadline)
                #endif
                captionsFontColorPicker
                showCaptionsAutoShowToggle

                #if !os(tvOS)
                    captionDefaultLanguagePicker
                    captionFallbackLanguagePicker
                #else
                    Button(action: { isShowingDefaultLanguagePicker = true }) {
                        HStack {
                            Text("Default language")
                            Spacer()
                            Text("\(LanguageCodes(rawValue: captionsDefaultLanguageCode)!.description.capitalized) (\(captionsDefaultLanguageCode))").foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity).sheet(isPresented: $isShowingDefaultLanguagePicker) {
                        defaultLanguagePickerTVOS(
                            selectedLanguage: $captionsDefaultLanguageCode,
                            isShowing: $isShowingDefaultLanguagePicker
                        )
                    }

                    Button(action: { isShowingFallbackLanguagePicker = true }) {
                        HStack {
                            Text("Fallback language")
                            Spacer()
                            Text("\(LanguageCodes(rawValue: captionsFallbackLanguageCode)!.description.capitalized) (\(captionsFallbackLanguageCode))").foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity).sheet(isPresented: $isShowingDefaultLanguagePicker) {
                        fallbackLanguagePickerTVOS(
                            selectedLanguage: $captionsFallbackLanguageCode,
                            isShowing: $isShowingFallbackLanguagePicker
                        )
                    }
                #endif
            }

            #if !os(tvOS)
                Section(header: SettingsHeader(text: "Chapters".localized())) {
                    showChaptersToggle
                    showThumbnailsToggle
                    showThumbnailsWhenDifferentToggle
                    expandChaptersToggle
                }
            #endif

            let interface = Section(header: SettingsHeader(text: "Interface".localized())) {
                #if os(iOS)
                    if idiom == .pad {
                        sidebarPicker
                    }
                #endif

                #if os(macOS)
                    sidebarPicker
                #endif

                if !accounts.isEmpty {
                    keywordsToggle

                    commentsToggle
                    #if !os(tvOS)
                        showScrollToTopInCommentsToggle
                    #endif

                    returnYouTubeDislikeToggle
                }
            }

            #if os(tvOS)
                if !accounts.isEmpty {
                    interface
                }
            #elseif os(macOS)
                interface
            #elseif os(iOS)
                if idiom == .pad || !accounts.isEmpty {
                    interface
                }
            #endif

            #if os(iOS)
                Section(header: SettingsHeader(text: "Fullscreen".localized())) {
                    if Constants.isIPad {
                        enterFullscreenInLandscapeToggle
                    }

                    exitFullscreenOnEOFToggle
                    rotateToLandscapeOnEnterFullScreenPicker
                }
            #endif

            Section(header: SettingsHeader(text: "Picture in Picture".localized())) {
                closePiPOnNavigationToggle
                closePiPOnOpeningPlayerToggle
                closePlayerOnOpeningPiPToggle
                #if !os(macOS)
                    closePiPAndOpenPlayerOnEnteringForegroundToggle
                #endif
            }
        }
    }

    private var videoDetailsHeaderPadding: Double {
        #if os(macOS)
            5.0
        #else
            0.0
        #endif
    }

    private var sourcePicker: some View {
        Picker("Source", selection: $playerInstanceID) {
            Text("Instance of current account").tag(String?.none)

            ForEach(instances) { instance in
                Text(instance.description).tag(Optional(instance.id))
            }
        }
        .modifier(SettingsPickerModifier())
    }

    private var sidebarPicker: some View {
        Picker("Sidebar", selection: $playerSidebar) {
            #if os(macOS)
                Text("Show sidebar").tag(PlayerSidebarSetting.always)
            #endif

            #if os(iOS)
                Text("Show sidebar when space permits").tag(PlayerSidebarSetting.whenFits)
            #endif

            Text("Hide sidebar").tag(PlayerSidebarSetting.never)
        }
        .modifier(SettingsPickerModifier())
    }

    private var commentsToggle: some View {
        Toggle("Show comments", isOn: $showComments)
    }

    #if !os(tvOS)
        private var showScrollToTopInCommentsToggle: some View {
            Toggle("Show scroll to top button in comments", isOn: $showScrollToTopInComments).disabled(!showComments)
        }
    #endif

    private var keywordsToggle: some View {
        Toggle("Show keywords", isOn: $showKeywords)
    }

    private var expandVideoDescriptionToggle: some View {
        Toggle("Open video description expanded", isOn: $expandVideoDescription)
    }

    #if !os(tvOS)
        private var collapsedLineDescriptionStepper: some View {
            LazyVStack {
                Stepper(value: $collapsedLinesDescription, in: 0 ... 10) {
                    Text("Description preview")
                    #if os(macOS)
                        Spacer()
                    #endif
                    if collapsedLinesDescription == 0 {
                        Text("No preview")
                    } else {
                        Text("\(collapsedLinesDescription) lines")
                    }
                }
            }
        }
    #endif

    private var returnYouTubeDislikeToggle: some View {
        Toggle("Enable Return YouTube Dislike", isOn: $enableReturnYouTubeDislike)
    }

    private var pauseOnHidingPlayerToggle: some View {
        Toggle("Pause when player is closed", isOn: $pauseOnHidingPlayer)
    }

    private var closeVideoOnEOFToggle: some View {
        Toggle("Close video and player on end", isOn: $closeVideoOnEOF)
    }

    #if !os(tvOS)
        private var exitFullscreenOnEOFToggle: some View {
            Toggle("Exit fullscreen on end", isOn: $exitFullscreenOnEOF)
                .disabled(closeVideoOnEOF)
        }
    #endif

    #if !os(macOS)
        private var pauseOnEnteringBackgroundToogle: some View {
            Toggle("Pause when entering background", isOn: $pauseOnEnteringBackground)
        }
    #endif

    #if os(iOS)
        private var enterFullscreenInLandscapeToggle: some View {
            Toggle("Enter fullscreen in landscape orientation", isOn: $enterFullscreenInLandscape)
                .disabled(lockPortraitWhenBrowsing)
        }

        private var rotateToLandscapeOnEnterFullScreenPicker: some View {
            Picker("Default orientation", selection: $rotateToLandscapeOnEnterFullScreen) {
                Text("Landscape left").tag(FullScreenRotationSetting.landscapeLeft)
                Text("Landscape right").tag(FullScreenRotationSetting.landscapeRight)
            }
            .modifier(SettingsPickerModifier())
        }
    #endif

    private var closePiPOnNavigationToggle: some View {
        Toggle("Close PiP when starting playing other video", isOn: $closePiPOnNavigation)
    }

    private var closePiPOnOpeningPlayerToggle: some View {
        Toggle("Close PiP when player is opened", isOn: $closePiPOnOpeningPlayer)
    }

    private var closePlayerOnOpeningPiPToggle: some View {
        Toggle("Close player when starting PiP", isOn: $closePlayerOnOpeningPiP)
    }

    #if !os(macOS)
        private var closePiPAndOpenPlayerOnEnteringForegroundToggle: some View {
            Toggle("Close PiP and open player when application enters foreground", isOn: $closePiPAndOpenPlayerOnEnteringForeground)
        }
    #endif

    private var showCaptionsAutoShowToggle: some View {
        Toggle("Always show captions", isOn: $captionsAutoShow)
    }

    private var captionsFontScaleSizePicker: some View {
        Picker("Size", selection: $captionsFontScaleSize) {
            Text("Small").tag(String("0.725"))
            Text("Medium").tag(String("1.0"))
            Text("Large").tag(String("1.5"))
        }
        .onChange(of: captionsFontScaleSize) { _ in
            PlayerModel.shared.mpvBackend.client.setSubFontSize(scaleSize: captionsFontScaleSize)
        }
        #if os(macOS)
        .labelsHidden()
        #endif
    }

    private var captionsFontColorPicker: some View {
        Picker("Color", selection: $captionsFontColor) {
            Text("White").tag(String("#FFFFFF"))
            Text("Yellow").tag(String("#FFFF00"))
            Text("Red").tag(String("#FF0000"))
            Text("Orange").tag(String("#FFA500"))
            Text("Green").tag(String("#008000"))
            Text("Blue").tag(String("#0000FF"))
        }
        .onChange(of: captionsFontColor) { _ in
            PlayerModel.shared.mpvBackend.client.setSubFontColor(color: captionsFontColor)
        }
        #if os(macOS)
        .labelsHidden()
        #endif
    }

    #if !os(tvOS)
        private var captionDefaultLanguagePicker: some View {
            Picker("Default language", selection: $captionsDefaultLanguageCode) {
                ForEach(LanguageCodes.allCases, id: \.self) { language in
                    Text("\(language.description.capitalized) (\(language.rawValue))").tag(language.rawValue)
                }
            }
            #if os(macOS)
            .labelsHidden()
            #endif
        }

        private var captionFallbackLanguagePicker: some View {
            Picker("Fallback language", selection: $captionsFallbackLanguageCode) {
                ForEach(LanguageCodes.allCases, id: \.self) { language in
                    Text("\(language.description.capitalized) (\(language.rawValue))").tag(language.rawValue)
                }
            }
            #if os(macOS)
            .labelsHidden()
            #endif
        }
    #else
        struct defaultLanguagePickerTVOS: View {
            @Binding var selectedLanguage: String
            @Binding var isShowing: Bool

            var body: some View {
                NavigationView {
                    List(LanguageCodes.allCases, id: \.self) { language in
                        Button(action: {
                            selectedLanguage = language.rawValue
                            isShowing = false
                        }) {
                            Text("\(language.description.capitalized) (\(language.rawValue))")
                        }
                    }
                    .navigationTitle("Select Default Language")
                }
            }
        }

        struct fallbackLanguagePickerTVOS: View {
            @Binding var selectedLanguage: String
            @Binding var isShowing: Bool

            var body: some View {
                NavigationView {
                    List(LanguageCodes.allCases, id: \.self) { language in
                        Button(action: {
                            selectedLanguage = language.rawValue
                            isShowing = false
                        }) {
                            Text("\(language.description.capitalized) (\(language.rawValue))")
                        }
                    }
                    .navigationTitle("Select Fallback Language")
                }
            }
        }
    #endif

    #if !os(tvOS)
        private var inspectorVisibilityPicker: some View {
            Picker("Inspector", selection: $showInspector) {
                Text("Always").tag(ShowInspectorSetting.always)
                Text("Only for local files and URLs").tag(ShowInspectorSetting.onlyLocal)
            }
            #if os(macOS)
            .labelsHidden()
            #endif
        }

        private var showChaptersToggle: some View {
            Toggle("Show chapters", isOn: $showChapters)
        }

        private var showThumbnailsToggle: some View {
            Toggle("Show thumbnails", isOn: $showThumbnails)
                .disabled(!showChapters)
                .foregroundColor(showChapters ? .primary : .secondary)
        }

        private var showThumbnailsWhenDifferentToggle: some View {
            Toggle("Show thumbnails only when unique", isOn: $showThumbnailsOnlyWhenDifferent)
                .disabled(!showChapters || !showThumbnails)
                .foregroundColor(showChapters && showThumbnails ? .primary : .secondary)
        }

        private var expandChaptersToggle: some View {
            Toggle("Open vertical chapters expanded", isOn: $expandChapters)
                .disabled(!showChapters)
                .foregroundColor(showChapters ? .primary : .secondary)
        }

        private var showRelatedToggle: some View {
            Toggle("Related", isOn: $showRelated)
        }
    #endif
}

struct PlayerSettings_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading) {
            PlayerSettings()
        }
        .frame(minHeight: 800)
        .injectFixtureEnvironmentObjects()
    }
}
