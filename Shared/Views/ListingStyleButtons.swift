import SwiftUI

struct ListingStyleButtons: View {
    @Binding var listingStyle: ListingStyle

    var body: some View {
        #if os(iOS)
            picker
        #else
            Button {
                listingStyle = listingStyle.next()
            } label: {
                Label(listingStyle.rawValue.capitalized, systemImage: listingStyle.systemImage)
                #if os(tvOS)
                    .font(.caption)
                    .imageScale(.small)
                #endif
            }
        #endif
    }

    var picker: some View {
        Picker("Listing Style", selection: $listingStyle) {
            ForEach(ListingStyle.allCases, id: \.self) { style in
                Button {
                    listingStyle = style
                } label: {
                    Label(style.rawValue.capitalized, systemImage: style.systemImage)
                }
            }
        }
    }
}

struct ListingStyleButtons_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ListingStyleButtons(listingStyle: .constant(.cells))
        }
    }
}
