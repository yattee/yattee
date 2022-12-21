import SwiftUI

struct ClearQueueButton: View {
    private var navigation = NavigationModel.shared

    var body: some View {
        Button {
            navigation.presentAlert(
                Alert(
                    title: Text("Are you sure you want to clear the queue?"),
                    primaryButton: .destructive(Text("Clear All")) {
                        PlayerModel.shared.removeQueueItems()
                    },
                    secondaryButton: .cancel()
                )
            )
        } label: {
            Label("Clear Queue", systemImage: "trash")
                .font(.headline)
                .labelStyle(.iconOnly)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
    }
}

struct ClearQueueButton_Previews: PreviewProvider {
    static var previews: some View {
        ClearQueueButton()
    }
}
