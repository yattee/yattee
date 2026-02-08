//
//  VideoDetailsLoadState.swift
//  Yattee
//
//  Video details loading state definitions.
//

import Foundation

enum VideoDetailsLoadState: Equatable {
    case idle       // No video loaded
    case loading    // Fetching full details from API
    case loaded     // Full details available
    case error      // Failed to load details
}
