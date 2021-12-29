import SwiftUI

struct PlaceholderProgressView: View {
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            Spacer()
        }
    }
}

struct PlaceholderProgressView_Previews: PreviewProvider {
    static var previews: some View {
        PlaceholderProgressView()
    }
}
