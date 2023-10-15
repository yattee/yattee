//
//  RefreshControl.swift
//  SwiftUI_Pull_to_Refresh
//
//  Created by Geri Borbás on 18/09/2021.
//

import Combine
import Foundation
import SwiftUI
import UIKit

final class RefreshControl: ObservableObject {
    static var navigationBarTitleDisplayMode: NavigationBarItem.TitleDisplayMode {
        if #available(iOS 15.0, *) {
            return .automatic
        }

        return .inline
    }

    let onValueChanged: (_ refreshControl: UIRefreshControl) -> Void

    init(onValueChanged: @escaping ((UIRefreshControl) -> Void)) {
        self.onValueChanged = onValueChanged
    }

    /// Adds a `UIRefreshControl` to the `UIScrollView` provided.
    func add(to scrollView: UIScrollView) {
        scrollView.refreshControl = UIRefreshControl().withTarget(
            self,
            action: #selector(onValueChangedAction),
            for: .valueChanged
        )
        .testable(as: "RefreshControl")
    }

    @objc private func onValueChangedAction(sender: UIRefreshControl) {
        onValueChanged(sender)
    }
}

extension UIRefreshControl {
    /// Convinience method to assign target action inline.
    func withTarget(_ target: Any?, action: Selector, for controlEvents: UIControl.Event) -> UIRefreshControl {
        addTarget(target, action: action, for: controlEvents)
        return self
    }

    /// Convinience method to match refresh control for UI testing.
    func testable(as id: String) -> UIRefreshControl {
        isAccessibilityElement = true
        accessibilityIdentifier = id
        return self
    }
}
