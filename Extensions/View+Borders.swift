import Foundation
import SwiftUI

extension View {
    func borderTop(height: Double, color: Color = Color(white: 0.7, opacity: 1)) -> some View {
        verticalEdgeBorder(.top, height: height, color: color)
    }

    func borderBottom(height: Double, color: Color = Color(white: 0.7, opacity: 1)) -> some View {
        verticalEdgeBorder(.bottom, height: height, color: color)
    }

    private func verticalEdgeBorder(_ edge: Alignment, height: Double, color: Color) -> some View {
        overlay(Rectangle().frame(width: nil, height: height, alignment: .top).foregroundColor(color), alignment: edge)
    }
}
