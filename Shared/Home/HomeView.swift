import Defaults
import Siesta
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @ObservedObject private var accounts = AccountsModel.shared

    @State private var presentingEditFavorites = false
    @State private var favoritesChanged = false

    @FetchRequest(sortDescriptors: [.init(key: "watchedAt", ascending: false)])
    var watches: FetchedResults<Watch>
    @State private var historyID = UUID()
    #if os(iOS)
        @State private var recentDocumentsID = UUID()
    #endif

    var favoritesObserver: Any?

    #if !os(tvOS)
        @Default(.favorites) private var favorites
    #endif
    #if os(iOS)
        @Default(.homeRecentDocumentsItems) private var homeRecentDocumentsItems
    #endif
    @Default(.homeHistoryItems) private var homeHistoryItems
    @Default(.showFavoritesInHome) private var showFavoritesInHome
    @Default(.showOpenActionsInHome) private var showOpenActionsInHome
    @Default(.showQueueInHome) private var showQueueInHome

    private var navigation: NavigationModel { .shared }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            HStack {
                #if os(tvOS)
                    Group {
                        if showOpenActionsInHome {
                            AccentButton(text: "Open Video", imageSystemName: "globe") {
                                NavigationModel.shared.presentingOpenVideos = true
                            }
                        }
                        AccentButton(text: "Locations", imageSystemName: "globe") {
                            NavigationModel.shared.presentingAccounts = true
                        }
                        AccentButton(text: "Settings", imageSystemName: "gear") {
                            NavigationModel.shared.presentingSettings = true
                        }
                    }
                #else
                    if showOpenActionsInHome {
                        AccentButton(text: "Files", imageSystemName: "folder") {
                            NavigationModel.shared.presentingFileImporter = true
                        }
                        AccentButton(text: "Paste", imageSystemName: "doc.on.clipboard.fill") {
                            OpenVideosModel.shared.openURLsFromClipboard(playbackMode: .playNow)
                        }
                        AccentButton(imageSystemName: "ellipsis") {
                            NavigationModel.shared.presentingOpenVideos = true
                        }
                        .frame(maxWidth: 40)
                    }
                #endif
            }
            .padding(.top, 15)
            #if os(tvOS)
                .padding(.horizontal, 40)
            #else
                .padding(.horizontal, 15)
            #endif

            if showQueueInHome {
                QueueView()
                #if os(tvOS)
                    .padding(.horizontal, 40)
                #else
                    .padding(.horizontal, 15)
                #endif
            }

            if !accounts.current.isNil, showFavoritesInHome {
                LazyVStack(alignment: .leading) {
                    #if os(tvOS)
                        ForEach(Defaults[.favorites]) { item in
                            FavoriteItemView(item: item)
                        }
                    #else
                        ForEach(favorites) { item in
                            FavoriteItemView(item: item)
                            #if os(macOS)
                                .workaroundForVerticalScrollingBug()
                            #endif
                        }
                    #endif
                }
            }

            #if os(iOS)
                if homeRecentDocumentsItems > 0 {
                    VStack {
                        HStack {
                            NavigationLink(destination: DocumentsView()) {
                                HStack {
                                    Text("Documents")
                                        .font(.title3.bold())
                                    Image(systemName: "chevron.right")
                                        .imageScale(.small)
                                }
                                .lineLimit(1)
                            }
                            .padding(.leading, 15)

                            Spacer()

                            Button {
                                recentDocumentsID = UUID()
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                                    .font(.headline)
                                    .labelStyle(.iconOnly)
                                    .foregroundColor(.secondary)
                            }
                        }

                        RecentDocumentsView(limit: homeRecentDocumentsItems)
                            .id(recentDocumentsID)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    #if os(tvOS)
                        .padding(.trailing, 40)
                    #else
                        .padding(.trailing, 15)
                    #endif
                }
            #endif

            if homeHistoryItems > 0 {
                VStack {
                    HStack {
                        sectionLabel("History")
                        Spacer()
                        Button {
                            navigation.presentAlert(
                                Alert(
                                    title: Text("Are you sure you want to clear history of watched videos?"),
                                    message: Text("This cannot be reverted"),
                                    primaryButton: .destructive(Text("Clear All")) {
                                        PlayerModel.shared.removeHistory()
                                        historyID = UUID()
                                    },
                                    secondaryButton: .cancel()
                                )
                            )
                        } label: {
                            Label("Clear History", systemImage: "trash")
                                .font(.headline)
                                .labelStyle(.iconOnly)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    #if os(tvOS)
                        .padding(.trailing, 40)
                    #else
                        .padding(.trailing, 15)
                    #endif

                    HistoryView(limit: homeHistoryItems)
                    #if os(tvOS)
                        .padding(.horizontal, 40)
                    #else
                        .padding(.horizontal, 15)
                    #endif
                        .id(historyID)
                }
            }

            #if !os(tvOS)
                Color.clear.padding(.bottom, 60)
            #endif
        }
        .onAppear {
            Defaults.observe(.favorites) { _ in
                favoritesChanged.toggle()
            }
            .tieToLifetime(of: accounts)
        }

        .redrawOn(change: favoritesChanged)

        #if os(tvOS)
            .edgesIgnoringSafeArea(.horizontal)
        #else
            .navigationTitle("Home")
        #endif
        #if os(macOS)
        .background(Color.secondaryBackground)
        .frame(minWidth: 360)
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                homeMenu
            }
        }
        #endif
        #if !os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            favoritesChanged.toggle()
        }
        #endif
    }

    func sectionLabel(_ label: String) -> some View {
        Text(label.localized())
        #if os(tvOS)
            .padding(.horizontal, 40)
        #else
            .padding(.horizontal, 15)
        #endif
            .font(.title3.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundColor(.secondary)
    }

#if os(iOS)
        var homeMenu: some View {
            Menu {
                Section {
                    HideWatchedButtons()
                    HideShortsButtons()
                }
            } label: {
                HStack(spacing: 12) {
                    Text("Home")
                        .foregroundColor(.primary)
                        .font(.headline)

                    Image(systemName: "chevron.down.circle.fill")
                        .foregroundColor(.accentColor)
                        .imageScale(.small)
                }
                .transaction { t in t.animation = nil }
            }
        }
    #endif
}

struct Home_Previews: PreviewProvider {
    static var previews: some View {
        TabView {
            NavigationView {
                HomeView()
                    .injectFixtureEnvironmentObjects()
                    .tabItem {
                        Label("Home", systemImage: "house")
                    }
            }
        }
    }
}
