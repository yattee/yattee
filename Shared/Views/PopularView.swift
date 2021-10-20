import Siesta
import SwiftUI

struct PopularView: View {
    @StateObject private var store = Store<[Video]>()

    @EnvironmentObject<AccountsModel> private var accounts

    var resource: Resource? {
        accounts.api.popular
    }

    var body: some View {
        PlayerControlsView {
            VideosCellsVertical(videos: store.collection)
                .onAppear {
                    resource?.addObserver(store)
                    resource?.loadIfNeeded()
                }
            #if !os(tvOS)
                .navigationTitle("Popular")
            #endif
        }
    }
}
