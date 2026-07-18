//
//  View+Conditional.swift
//  Yattee
//
//  Conditional view modifier extension.
//

import SwiftUI

extension View {
    /// Conditionally applies a transformation to the view.
    @ViewBuilder
    func `if`<Transform: View>(
        _ condition: Bool,
        transform: (Self) -> Transform
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Conditionally applies one of two transformations.
    @ViewBuilder
    func `if`<TrueContent: View, FalseContent: View>(
        _ condition: Bool,
        then trueTransform: (Self) -> TrueContent,
        else falseTransform: (Self) -> FalseContent
    ) -> some View {
        if condition {
            trueTransform(self)
        } else {
            falseTransform(self)
        }
    }

    /// Conditionally applies a transformation when an optional value is present.
    @ViewBuilder
    func ifLet<T, Transform: View>(
        _ value: T?,
        transform: (Self, T) -> Transform
    ) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}
