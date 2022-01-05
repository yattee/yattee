//
//  UIResponder+Extensions.swift
//  SwiftUI_Pull_to_Refresh
//
//  Created by Geri Borbás on 21/09/2021.
//

import Foundation
import UIKit

extension UIResponder {
    var parentViewController: UIViewController? {
        next as? UIViewController ?? next?.parentViewController
    }
}
