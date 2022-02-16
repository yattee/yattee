import SwiftUI

struct ToggleBackendButton: View {
    @EnvironmentObject<PlayerControlsModel> private var controls
    @EnvironmentObject<PlayerModel> private var player

    var body: some View {
        Button {
            player.saveTime {
                player.changeActiveBackend(from: player.activeBackend, to: player.activeBackend.next())
                controls.resetTimer()
            }
        } label: {
            Text(player.activeBackend.label)
        }
    }
}

struct ToggleBackendButton_Previews: PreviewProvider {
    static var previews: some View {
        ToggleBackendButton()
    }
}
