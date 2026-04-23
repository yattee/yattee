//
//  SearchHistory.swift
//  Yattee
//
//  SwiftData model for search history.
//

import Foundation
import SwiftData

@Model
final class SearchHistory {
    var id: UUID
    var query: String
    var searchedAt: Date
    
    init(id: UUID = UUID(), query: String, searchedAt: Date = Date()) {
        self.id = id
        self.query = query
        self.searchedAt = searchedAt
    }
}
