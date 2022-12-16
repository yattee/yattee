import Siesta
import SwiftUI

struct RequestErrorButton: View {
    var error: RequestError?

    var body: some View {
        if let error {
            Button {
                NavigationModel.shared.presentRequestErrorAlert(error)
            } label: {
                Label("Error", systemImage: "exclamationmark.circle.fill")
                    .foregroundColor(Color("AppRedColor"))
            }
        }
    }
}

struct RequestErrorButton_Previews: PreviewProvider {
    static var previews: some View {
        RequestErrorButton()
    }
}
