import SwiftUI

struct OpenSettingsButton: View {
    @Environment(\.dismiss) private var dismiss

    #if !os(macOS)
        @EnvironmentObject<NavigationModel> private var navigation
    #endif

    var body: some View {
        Button {
            dismiss()

            #if os(macOS)
                NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            #else
                navigation.presentingSettings = true
            #endif
        } label: {
            Label("Open Settings", systemImage: "gearshape.2")
        }
        .buttonStyle(.borderedProminent)
    }
}

struct OpenSettingsButton_Previews: PreviewProvider {
    static var previews: some View {
        OpenSettingsButton()
    }
}
