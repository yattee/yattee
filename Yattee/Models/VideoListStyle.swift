//
//  VideoListStyle.swift
//  Yattee
//
//  List style options for video list views.
//

import SwiftUI

/// Style type for list layout in video views.
enum VideoListStyle: String, CaseIterable, Codable {
    /// Inset style with card background, padding, and rounded corners
    case inset
    /// Plain style without card background, traditional list appearance
    case plain

    var displayName: LocalizedStringKey {
        switch self {
        case .inset: "viewOptions.listStyle.inset"
        case .plain: "viewOptions.listStyle.plain"
        }
    }
}
