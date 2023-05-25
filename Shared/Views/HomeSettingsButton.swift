import SwiftUI

struct HomeSettingsButton: View {
    var navigation = NavigationModel.shared

    var body: some View {
        Button {
            navigation.presentingHomeSettings = true
        } label: {
            Label("Home Settings", systemImage: "gear")
        }
        .font(.caption)
        .imageScale(.small)
    }
}

struct HomeSettingsButton_Previews: PreviewProvider {
    static var previews: some View {
        HomeSettingsButton()
    }
}
