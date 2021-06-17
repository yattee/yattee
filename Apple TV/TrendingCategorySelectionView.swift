import SwiftUI

struct TrendingCategorySelectionView: View {
    @Environment(\.presentationMode) private var presentationMode

    @Binding var selectedCategory: TrendingCategory

    var body: some View {
        ZStack {
            VisualEffectView(effect: UIBlurEffect(style: .dark))

            VStack(alignment: .leading) {
                Spacer()

                ForEach(TrendingCategory.allCases) { category in
                    Button(category.name) {
                        selectedCategory = category
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                .frame(width: 800)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .edgesIgnoringSafeArea(.all)
    }
}
