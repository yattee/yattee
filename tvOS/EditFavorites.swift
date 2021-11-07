import Defaults
import SwiftUI

struct EditFavorites: View {
    @EnvironmentObject<PlaylistsModel> private var playlistsModel

    private var model = FavoritesModel.shared

    @Default(.favorites) private var favorites

    var body: some View {
        VStack {
            ScrollView {
                ForEach(favorites) { item in
                    HStack {
                        Text(label(item))

                        Spacer()
                        HStack(spacing: 30) {
                            Button {
                                model.moveUp(item)
                            } label: {
                                Image(systemName: "arrow.up")
                            }

                            Button {
                                model.moveDown(item)
                            } label: {
                                Image(systemName: "arrow.down")
                            }

                            Button {
                                model.remove(item)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
                .padding(.trailing, 40)

                Divider()
                    .padding(20)

                ForEach(model.addableItems()) { item in
                    HStack {
                        Text(label(item))

                        Spacer()

                        Button {
                            model.add(item)
                        } label: {
                            Label("Add to Favorites", systemImage: "heart")
                        }
                    }
                }
                .padding(.trailing, 40)

                HStack {
                    Text("Add more Channels and Playlists to your Favorites using button")
                    Button {} label: {
                        Label("Add to Favorites", systemImage: "heart")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(true)
                }
                .foregroundColor(.secondary)
                .padding(.top, 80)
            }
            .frame(width: 1000, alignment: .leading)
        }
        .navigationTitle("Edit Favorites")
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
        EditFavorites()
            .injectFixtureEnvironmentObjects()
    }
}
