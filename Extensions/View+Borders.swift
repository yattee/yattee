import Foundation
import SwiftUI

extension View {
    func borderTop(height: Double, color: Color = Color(white: 0.7, opacity: 1)) -> some View {
        verticalEdgeBorder(.top, height: height, color: color)
    }

    func borderBottom(height: Double, color: Color = Color(white: 0.7, opacity: 1)) -> some View {
        verticalEdgeBorder(.bottom, height: height, color: color)
    }

    func borderLeading(width: Double, color: Color = Color(white: 0.7, opacity: 1)) -> some View {
        horizontalEdgeBorder(.leading, width: width, color: color)
    }

    func borderTrailing(width: Double, color: Color = Color(white: 0.7, opacity: 1)) -> some View {
        horizontalEdgeBorder(.trailing, width: width, color: color)
    }

    private func verticalEdgeBorder(_ edge: Alignment, height: Double, color: Color) -> some View {
        overlay(Rectangle().frame(width: nil, height: height, alignment: .top)
            .foregroundColor(color), alignment: edge)
    }

    private func horizontalEdgeBorder(_ edge: Alignment, width: Double, color: Color) -> some View {
        overlay(Rectangle().frame(width: width, height: nil, alignment: .leading)
            .foregroundColor(color), alignment: edge)
    }
}
