import SwiftUI

struct NetworkState: View {
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<NetworkStateModel> private var model

    var body: some View {
        Buffering(state: model.fullStateText)
            .opacity(visible ? 1 : 0)
    }

    var visible: Bool {
        player.isPlaying && (model.pausedForCache || player.isSeeking)
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
