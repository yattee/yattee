import SwiftUI

struct ViewOptionsView: View {
    @EnvironmentObject private var profile: Profile

    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        ZStack {
            VisualEffectView(effect: UIBlurEffect(style: .dark))

            VStack {
                Spacer()

                ScrollView(.vertical) {
                    Button(profile.listing == .list ? "Cells" : "List") {
                        profile.listing = (profile.listing == .list ? .cells : .list)
                        presentationMode.wrappedValue.dismiss()
                    }

                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .frame(width: 800)
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .edgesIgnoringSafeArea(.all)
    }
}
