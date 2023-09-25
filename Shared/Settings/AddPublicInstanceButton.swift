import SwiftUI

struct AddPublicInstanceButton: View {
    @ObservedObject private var accounts = AccountsModel.shared

    @State private var id = UUID().uuidString

    var body: some View {
        if let account = accounts.current, let app = account.app, account.isPublic, !account.isPublicAddedToCustom {
            Button {
                _ = InstancesModel.shared.add(app: app, name: "", url: account.urlString)
                regenerateID()
            } label: {
                Label(String(format: "Add %@", account.urlString), systemImage: "plus")
            }
            .id(id)
        }
    }

    private func regenerateID() {
        id = UUID().uuidString
    }
}

struct AddPublicInstanceButton_Previews: PreviewProvider {
    static var previews: some View {
        AddPublicInstanceButton()
    }
}
