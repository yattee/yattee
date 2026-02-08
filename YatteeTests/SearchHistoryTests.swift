//
//  SearchHistoryTests.swift
//  YatteeTests
//
//  Tests for search history functionality.
//

import Testing
import Foundation
@testable import Yattee

@MainActor
@Suite("Search History Tests")
struct SearchHistoryTests {
    
    @Test("Add search query creates new entry")
    @MainActor
    func addSearchQuery() async throws {
        let dataManager = try DataManager(inMemory: true)
        let settingsManager = SettingsManager()
        dataManager.settingsManager = settingsManager
        settingsManager.searchHistoryLimit = 25
        
        dataManager.addSearchQuery("swift programming")
        
        let history = dataManager.fetchSearchHistory(limit: 10)
        #expect(history.count == 1)
        #expect(history.first?.query == "swift programming")
    }
    
    @Test("Duplicate query moves to top with case-insensitive matching")
    @MainActor
    func duplicateQueryDeduplication() async throws {
        let dataManager = try DataManager(inMemory: true)
        let settingsManager = SettingsManager()
        dataManager.settingsManager = settingsManager
        settingsManager.searchHistoryLimit = 25
        
        // Add three queries
        dataManager.addSearchQuery("swift")
        try await Task.sleep(for: .milliseconds(10)) // Small delay to ensure different timestamps
        dataManager.addSearchQuery("python")
        try await Task.sleep(for: .milliseconds(10))
        dataManager.addSearchQuery("Swift") // Same as first but different case
        
        let history = dataManager.fetchSearchHistory(limit: 10)
        
        // Should only have 2 entries (swift deduplicated)
        #expect(history.count == 2)
        
        // "Swift" should be at top (most recent)
        #expect(history[0].query == "swift")
        #expect(history[1].query == "python")
    }
    
    @Test("Enforces user-configured limit")
    @MainActor
    func searchHistoryLimit() async throws {
        let dataManager = try DataManager(inMemory: true)
        let settingsManager = SettingsManager()
        dataManager.settingsManager = settingsManager
        settingsManager.searchHistoryLimit = 5
        
        // Add 10 queries
        for i in 1...10 {
            dataManager.addSearchQuery("query \(i)")
        }
        
        let history = dataManager.fetchSearchHistory(limit: 100)
        
        // Should only keep last 5
        #expect(history.count == 5)
        #expect(history[0].query == "query 10")
        #expect(history[4].query == "query 6")
    }
    
    @Test("Delete removes specific entry")
    @MainActor
    func deleteSearchQuery() async throws {
        let dataManager = try DataManager(inMemory: true)
        let settingsManager = SettingsManager()
        dataManager.settingsManager = settingsManager
        
        dataManager.addSearchQuery("query 1")
        dataManager.addSearchQuery("query 2")
        dataManager.addSearchQuery("query 3")
        
        var history = dataManager.fetchSearchHistory(limit: 10)
        #expect(history.count == 3)
        
        // Delete middle entry
        let toDelete = history[1]
        dataManager.deleteSearchQuery(toDelete)
        
        history = dataManager.fetchSearchHistory(limit: 10)
        #expect(history.count == 2)
        #expect(history[0].query == "query 3")
        #expect(history[1].query == "query 1")
    }
    
    @Test("Clear all removes all entries")
    @MainActor
    func clearAllSearchHistory() async throws {
        let dataManager = try DataManager(inMemory: true)
        let settingsManager = SettingsManager()
        dataManager.settingsManager = settingsManager
        
        dataManager.addSearchQuery("query 1")
        dataManager.addSearchQuery("query 2")
        dataManager.addSearchQuery("query 3")
        
        var history = dataManager.fetchSearchHistory(limit: 10)
        #expect(history.count == 3)
        
        dataManager.clearSearchHistory()
        
        history = dataManager.fetchSearchHistory(limit: 10)
        #expect(history.isEmpty)
    }
    
    @Test("Whitespace trimming and empty query rejection")
    @MainActor
    func queryTrimming() async throws {
        let dataManager = try DataManager(inMemory: true)
        let settingsManager = SettingsManager()
        dataManager.settingsManager = settingsManager
        
        // Try to add empty query
        dataManager.addSearchQuery("")
        var history = dataManager.fetchSearchHistory(limit: 10)
        #expect(history.isEmpty)
        
        // Try to add whitespace-only query
        dataManager.addSearchQuery("   ")
        history = dataManager.fetchSearchHistory(limit: 10)
        #expect(history.isEmpty)
        
        // Add query with leading/trailing whitespace
        dataManager.addSearchQuery("  swift programming  ")
        history = dataManager.fetchSearchHistory(limit: 10)
        #expect(history.count == 1)
        #expect(history.first?.query == "swift programming")
    }
}
