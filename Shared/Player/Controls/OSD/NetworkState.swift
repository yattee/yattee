import SwiftUI

struct NetworkState: View {
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<NetworkStateModel> private var model

    var body: some View {
        Buffering(state: model.fullStateText)
            .opacity(model.pausedForCache || player.isSeeking ? 1 : 0)
    }
}

struct NetworkState_Previews: PreviewProvider {
    static var previews: some View {
        let networkState = NetworkStateModel()
        networkState.bufferingState = 30

        return NetworkState()
            .environmentObject(networkState)
            .environmentObject(PlayerModel())
    }
}
