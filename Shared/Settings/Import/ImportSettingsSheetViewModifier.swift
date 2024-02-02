import Foundation
import SwiftUI
import SwiftyJSON

struct ImportSettingsSheetViewModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var settingsFile: URL?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                ImportSettingsSheetView(settingsFile: $settingsFile)
            }
    }
}

struct ImportSettingsSheetViewModifier_Previews: PreviewProvider {
    static var previews: some View {
        Text("")
            .modifier(
                ImportSettingsSheetViewModifier(
                    isPresented: .constant(true),
                    settingsFile: .constant(URL(string: "https://gist.githubusercontent.com/arekf/87b4d6702755b01139431dcb809f9fdc/raw/7bb5cdba3ffc0c479f5260430ddc43c4a79a7a72/yattee-177-iPhone.yatteesettings")!)
                )
            )
    }
}
