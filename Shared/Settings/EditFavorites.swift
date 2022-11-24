import Defaults
import SwiftUI

struct EditFavorites: View {
    private var playlistsModel = PlaylistsModel.shared
    private var model = FavoritesModel.shared

    @Default(.favorites) private var favorites

    var body: some View {
        Group {
            #if os(tvOS)
                ScrollView {
                    VStack {
                        editor
                    }
                }
                .frame(width: 1000)
            #else
                List {
                    editor
                }
            #endif
        }
        .navigationTitle("Favorites")
    }

    var editor: some View {
        Group {
            Section(header: Text("Favorites")) {
                if favorites.isEmpty {
                    Text("Favorites is empty")
                        .foregroundColor(.secondary)
                }
                ForEach(favorites) { item in
                    HStack {
                        Text(label(item))

                        Spacer()
                        HStack(spacing: 30) {
                            Button {
                                model.moveUp(item)
                            } label: {
                                Label("Move Up", systemImage: "arrow.up")
                            }

                            Button {
                                model.moveDown(item)
                            } label: {
                                Label("Move Down", systemImage: "arrow.down")
                            }

                            Button {
                                model.remove(item)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                        #if !os(tvOS)
                        .buttonStyle(.borderless)
                        #endif
                    }
                }
            }
            #if os(tvOS)
            .padding(.trailing, 40)
            #endif

            #if os(tvOS)
                Divider()
                    .padding(20)
            #endif

            if !model.addableItems().isEmpty {
                Section(header: Text("Available")) {
                    ForEach(model.addableItems()) { item in
                        HStack {
                            Text(label(item))

                            Spacer()

                            Button {
                                model.add(item)
                            } label: {
                                Label("Add to Favorites", systemImage: "heart")
                                #if os(tvOS)
                                    .font(.system(size: 30))
                                #endif
                            }
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

    func label(_ item: FavoriteItem) -> String {
        if case let .playlist(id) = item.section {
            return playlistsModel.find(id: id)?.title ?? "Playlist".localized()
        }

        return item.section.label.localized()
    }
}

struct EditFavorites_Previews: PreviewProvider {
    static var previews: some View {
        EditFavorites()
            .injectFixtureEnvironmentObjects()
    }
}
