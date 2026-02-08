//
//  CloudKitZoneManager.swift
//  Yattee
//
//  Manages CloudKit zone creation and configuration.
//

import CloudKit
import Foundation

/// Manages the CloudKit record zone for user data.
actor CloudKitZoneManager {
    // MARK: - Properties
    
    private let database: CKDatabase
    private let zone: CKRecordZone
    private var isZoneCreated = false
    
    // MARK: - Initialization
    
    init(database: CKDatabase) {
        self.database = database
        self.zone = RecordType.createZone()
    }
    
    // MARK: - Zone Management
    
    /// Returns the configured zone.
    func getZone() -> CKRecordZone {
        zone
    }
    
    /// Creates the custom zone if it doesn't exist.
    /// Safe to call multiple times - CloudKit handles idempotency.
    func createZoneIfNeeded() async throws {
        guard !isZoneCreated else { return }
        
        do {
            let result = try await database.modifyRecordZones(
                saving: [zone],
                deleting: []
            )
            
            if !result.saveResults.isEmpty {
                isZoneCreated = true
                await MainActor.run {
                    LoggingService.shared.logCloudKit("CloudKit zone '\(RecordType.zoneName)' created/verified")
                }
            }
        } catch let error as CKError where error.code == .zoneNotFound {
            // Zone doesn't exist, try creating again
            await MainActor.run {
                LoggingService.shared.logCloudKit("Zone not found, retrying creation")
            }
            throw error
        } catch {
            await MainActor.run {
                LoggingService.shared.logCloudKitError("Failed to create zone", error: error)
            }
            throw error
        }
    }
    
    /// Deletes the zone and all its records. Use for testing/reset only.
    func deleteZone() async throws {
        do {
            let result = try await database.modifyRecordZones(
                saving: [],
                deleting: [zone.zoneID]
            )
            
            if !result.deleteResults.isEmpty {
                isZoneCreated = false
                await MainActor.run {
                    LoggingService.shared.logCloudKit("CloudKit zone deleted")
                }
            }
        } catch {
            await MainActor.run {
                LoggingService.shared.logCloudKitError("Failed to delete zone", error: error)
            }
            throw error
        }
    }
    
    /// Fetches all zones in the private database.
    func fetchAllZones() async throws -> [CKRecordZone] {
        try await database.allRecordZones()
    }
}
