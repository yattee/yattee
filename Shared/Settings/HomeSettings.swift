import Defaults
import SwiftUI

struct HomeSettings: View {
    private var model = FavoritesModel.shared

    @Default(.favorites) private var favorites
    @Default(.showHome) private var showHome
    @Default(.showFavoritesInHome) private var showFavoritesInHome
    @Default(.showQueueInHome) private var showQueueInHome
    @Default(.showOpenActionsInHome) private var showOpenActionsInHome
    @Default(.showOpenActionsToolbarItem) private var showOpenActionsToolbarItem

    @ObservedObject private var accounts = AccountsModel.shared

    var body: some View {
        Group {
            #if os(tvOS)
                ScrollView {
                    LazyVStack {
                        homeSettings
                            .padding(.horizontal)
                        editor
                    }
                }
                .frame(width: 1000)
            #else
                List {
                    homeSettings
                    editor
                }
            #endif
        }
        .navigationTitle("Home Settings")
    }

    var editor: some View {
        Group {
            Section(header: SettingsHeader(text: "Favorites")) {
                if favorites.isEmpty {
                    Text("Favorites is empty")
                        .padding(.vertical)
                        .foregroundColor(.secondary)
                }
                ForEach(favorites) { item in
                    FavoriteItemEditor(item: item)
                }
            }
            #if os(tvOS)
            .padding(.trailing, 40)
            #endif

            if !model.addableItems().isEmpty {
                Section(header: SettingsHeader(text: "Available")) {
                    ForEach(model.addableItems()) { item in
                        HStack {
                            FavoriteItemLabel(item: item)

                            Spacer()

                            Button {
                                model.add(item)
                            } label: {
                                Label("Add to Favorites", systemImage: "heart")
                                #if os(tvOS)
                                    .font(.system(size: 30))
                                #endif
                            }
                            .help("Add to Favorites")
                            #if !os(tvOS)
                                .buttonStyle(.borderless)
                            #endif
                        }
                    }
                }
                #if os(tvOS)
                .padding(.trailing, 40)
                #endif
            }
        }
        .labelStyle(.iconOnly)
    }

    private var homeSettings: some View {
        Section(header: SettingsHeader(text: "Home".localized())) {
            #if !os(tvOS)
                if !accounts.isEmpty {
                    Toggle("Show Home", isOn: $showHome)
                }
            #endif
            Toggle("Show Open Videos quick actions", isOn: $showOpenActionsInHome)
            Toggle("Show Next in Queue", isOn: $showQueueInHome)

            if !accounts.isEmpty {
                Toggle("Show Favorites", isOn: $showFavoritesInHome)
            }
        }
    }
}

struct FavoriteItemLabel: View {
    var item: FavoriteItem
    var body: some View {
        Text(label)
            .fontWeight(.bold)
    }

    var label: String {
        switch item.section {
        case let .playlist(_, id):
            return PlaylistsModel.shared.find(id: id)?.title ?? "Playlist".localized()
        default:
            return item.section.label.localized()
        }
    }
}

struct FavoriteItemEditor: View {
    var item: FavoriteItem

    private var model: FavoritesModel { .shared }

    @State private var listingStyle = WidgetListingStyle.horizontalCells
    @State private var limit = 3

    @State private var presentingRemoveAlert = false

    @Default(.favorites) private var favorites

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                FavoriteItemLabel(item: item)

                Spacer()

                HStack(spacing: 10) {
                    FavoriteItemEditorButton(color: model.canMoveUp(item) ? .accentColor : .secondary) {
                        Label("Move Up", systemImage: "arrow.up")
                    } onTapGesture: {
                        model.moveUp(item)
                    }

                    FavoriteItemEditorButton(color: model.canMoveDown(item) ? .accentColor : .secondary) {
                        Label("Move Down", systemImage: "arrow.down")
                    } onTapGesture: {
                        model.moveDown(item)
                    }

                    FavoriteItemEditorButton(color: .init("AppRedColor")) {
                        Label("Remove", systemImage: "trash")
                    } onTapGesture: {
                        presentingRemoveAlert = true
                    }
                    .alert(isPresented: $presentingRemoveAlert) {
                        Alert(
                            title: Text(
                                String(
                                    format: "Are you sure you want to remove %@ from Favorites?".localized(),
                                    item.section.label.localized()
                                )
                            ),
                            message: Text("This cannot be reverted"),
                            primaryButton: .destructive(Text("Remove")) {
                                model.remove(item)
                            },
                            secondaryButton: .cancel()
                        )
                    }
                }
            }

            listingStylePicker
                .padding(.vertical, 5)

            limitInput

            #if !os(iOS)
                Divider()
            #endif
        }
        .onAppear(perform: setupEditor)
        #if !os(tvOS)
            .buttonStyle(.borderless)
        #endif
    }

    var listingStylePicker: some View {
        Picker("Listing Style", selection: $listingStyle) {
            Text("Cells").tag(WidgetListingStyle.horizontalCells)
            Text("List").tag(WidgetListingStyle.list)
        }
        .onChange(of: listingStyle) { newValue in
            model.setListingStyle(newValue, item)
            limit = min(limit, WidgetSettings.maxLimit(newValue))
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }

    var limitInput: some View {
        HStack {
            Text("Limit")
            Spacer()

            #if !os(tvOS)
                limitMinusButton
                    .disabled(limit == 1)
            #endif

            #if os(tvOS)
                let textFieldWidth = 100.00
            #else
                let textFieldWidth = 30.00
            #endif

            TextField("Limit", value: $limit, formatter: NumberFormatter())
            #if !os(macOS)
                .keyboardType(.numberPad)
            #endif
                .labelsHidden()
                .frame(width: textFieldWidth, alignment: .trailing)
                .multilineTextAlignment(.center)
                .onChange(of: limit) { newValue in
                    let value = min(limit, WidgetSettings.maxLimit(listingStyle))
                    if newValue <= 0 || newValue != value {
                        limit = value
                    } else {
                        model.setLimit(value, item)
                    }
                }
            #if !os(tvOS)
                limitPlusButton
                    .disabled(limit == WidgetSettings.maxLimit(listingStyle))
            #endif
        }
    }

    #if !os(tvOS)
        var limitMinusButton: some View {
            FavoriteItemEditorButton {
                Label("Minus", systemImage: "minus")
            } onTapGesture: {
                limit = max(1, limit - 1)
            }
        }

        var limitPlusButton: some View {
            FavoriteItemEditorButton {
                Label("Plus", systemImage: "plus")
            } onTapGesture: {
                limit = max(1, limit + 1)
            }
        }
    #endif

    func setupEditor() {
        listingStyle = model.listingStyle(item)
        limit = model.limit(item)
    }
}

struct FavoriteItemEditorButton<LabelView: View>: View {
    var color = Color.accentColor
    var label: LabelView
    var onTapGesture: () -> Void = {}

    init(
        color: Color = .accentColor,
        @ViewBuilder label: () -> LabelView,
        onTapGesture: @escaping () -> Void = {}
    ) {
        self.color = color
        self.label = label()
        self.onTapGesture = onTapGesture
    }

    var body: some View {
        #if os(tvOS)
            Button(action: onTapGesture) {
                label
            }
        #else
            label
                .imageScale(.medium)
                .labelStyle(.iconOnly)
                .padding(7)
                .frame(minWidth: 40, minHeight: 40)
                .foregroundColor(color)
                .accessibilityAddTraits(.isButton)
            #if os(iOS)
                .background(RoundedRectangle(cornerRadius: 4).strokeBorder(lineWidth: 1).foregroundColor(color))
            #endif
                .contentShape(Rectangle())
                .onTapGesture(perform: onTapGesture)
        #endif
    }
}

struct HomeSettings_Previews: PreviewProvider {
    static var previews: some View {
        HomeSettings()
            .injectFixtureEnvironmentObjects()
    }
}
