import Defaults
import SwiftUI

struct EditFavorites: View {
    @EnvironmentObject<PlaylistsModel> private var playlistsModel

    private var model = FavoritesModel.shared

    @Default(.favorites) private var favorites

    var body: some View {
        Group {
            List {
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
                        }
                    }
                }
                #if os(tvOS)
                .padding(.trailing, 40)
                #endif
            }
            .labelStyle(.iconOnly)
            .frame(alignment: .leading)
            #if os(tvOS)
                .frame(width: 1000)
            #endif
        }
        .navigationTitle("Favorites")
    }

    func label(_ item: FavoriteItem) -> String {
        if case let .playlist(id) = item.section {
            return playlistsModel.find(id: id)?.title ?? "Playlist"
        }

        return item.section.label
    }
}

struct EditFavorites_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            EditFavorites()
        }
        .injectFixtureEnvironmentObjects()
    }
}
