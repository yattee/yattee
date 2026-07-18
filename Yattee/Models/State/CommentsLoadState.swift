//
//  CommentsLoadState.swift
//  Yattee
//
//  Comments loading state definitions.
//

import Foundation

enum CommentsLoadState: Equatable {
    case idle
    case loading
    case loaded
    case loadingMore
    case disabled
    case error
}
