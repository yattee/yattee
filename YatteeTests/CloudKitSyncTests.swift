//
//  CloudKitSyncTests.swift
//  YatteeTests
//
//  Tests for CloudKit record mapping and conflict resolution.
//

import CloudKit
import Foundation
import Testing
@testable import Yattee

@Suite("CloudKit Sync")
struct CloudKitSyncTests {

    @MainActor
    private static func makeMapper() -> CloudKitRecordMapper {
        CloudKitRecordMapper(zone: CKRecordZone(zoneName: RecordType.zoneName))
    }

    @MainActor
    private static func makeEntry(
        videoID: String = "video1",
        watchedSeconds: TimeInterval = 0,
        duration: TimeInterval = 0,
        isLive: Bool = false,
        updatedAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> WatchEntry {
        let entry = WatchEntry(
            videoID: videoID,
            sourceRawValue: "global",
            title: "Video",
            authorName: "Channel",
            authorID: "ch1",
            duration: duration,
            watchedSeconds: watchedSeconds,
            isLive: isLive
        )
        entry.updatedAt = updatedAt
        return entry
    }

    @MainActor
    private static func makeNotificationSettings(
        channelID: String = "channel1",
        notificationsEnabled: Bool = false,
        updatedAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> ChannelNotificationSettings {
        let settings = ChannelNotificationSettings(
            channelID: channelID,
            notificationsEnabled: notificationsEnabled,
            sourceRawValue: "global",
            globalProvider: "youtube"
        )
        settings.updatedAt = updatedAt
        return settings
    }

    // MARK: - Record Mapper

    @Suite("Record Mapper")
    struct RecordMapperTests {
        @Test("isLive survives the record round-trip")
        @MainActor
        func liveFlagRoundTrip() throws {
            let mapper = CloudKitSyncTests.makeMapper()
            let record = mapper.toCKRecord(watchEntry: CloudKitSyncTests.makeEntry(isLive: true))

            #expect(record["isLive"] as? Int64 == 1)

            let decoded = try mapper.toWatchEntry(from: record)
            #expect(decoded.isLive)
        }

        @Test("Records from older clients without isLive read as not live")
        @MainActor
        func missingLiveFlagReadsFalse() throws {
            let mapper = CloudKitSyncTests.makeMapper()
            let record = mapper.toCKRecord(watchEntry: CloudKitSyncTests.makeEntry(isLive: true))
            // Simulate a record written before the field existed
            record["isLive"] = nil

            let decoded = try mapper.toWatchEntry(from: record)
            #expect(!decoded.isLive)
        }
    }

    // MARK: - Conflict Resolution

    @Suite("Watch Entry Conflicts")
    struct WatchEntryConflictTests {
        @Test("Newer local live watch keeps its isLive flag over an old server record")
        @MainActor
        func localLiveWinsOverStaleServer() async throws {
            let mapper = CloudKitSyncTests.makeMapper()
            let local = mapper.toCKRecord(watchEntry: CloudKitSyncTests.makeEntry(
                isLive: true,
                updatedAt: Date(timeIntervalSince1970: 2_000)
            ))
            let server = mapper.toCKRecord(watchEntry: CloudKitSyncTests.makeEntry(
                watchedSeconds: 1_234,
                duration: 3_600,
                updatedAt: Date(timeIntervalSince1970: 1_000)
            ))
            // Old clients never wrote the field at all
            server["isLive"] = nil

            let resolver = CloudKitConflictResolver()
            let resolved = await resolver.resolveWatchEntryConflict(local: local, server: server)

            #expect(resolved["isLive"] as? Int64 == 1)
            #expect(resolved["watchedSeconds"] as? Double == 0)
        }

        @Test("Newer local VOD heal clears a stale live flag on the server")
        @MainActor
        func localVODHealClearsServerLiveFlag() async throws {
            let mapper = CloudKitSyncTests.makeMapper()
            let local = mapper.toCKRecord(watchEntry: CloudKitSyncTests.makeEntry(
                watchedSeconds: 300,
                duration: 1_200,
                updatedAt: Date(timeIntervalSince1970: 2_000)
            ))
            let server = mapper.toCKRecord(watchEntry: CloudKitSyncTests.makeEntry(
                isLive: true,
                updatedAt: Date(timeIntervalSince1970: 1_000)
            ))

            let resolver = CloudKitConflictResolver()
            let resolved = await resolver.resolveWatchEntryConflict(local: local, server: server)

            #expect(resolved["isLive"] as? Int64 == 0)
            #expect(resolved["watchedSeconds"] as? Double == 300)
        }

        @Test("Newer server record keeps its isLive flag")
        @MainActor
        func newerServerLiveFlagWins() async throws {
            let mapper = CloudKitSyncTests.makeMapper()
            let local = mapper.toCKRecord(watchEntry: CloudKitSyncTests.makeEntry(
                watchedSeconds: 500,
                duration: 3_600,
                updatedAt: Date(timeIntervalSince1970: 1_000)
            ))
            let server = mapper.toCKRecord(watchEntry: CloudKitSyncTests.makeEntry(
                isLive: true,
                updatedAt: Date(timeIntervalSince1970: 2_000)
            ))

            let resolver = CloudKitConflictResolver()
            let resolved = await resolver.resolveWatchEntryConflict(local: local, server: server)

            #expect(resolved["isLive"] as? Int64 == 1)
            #expect(resolved["watchedSeconds"] as? Double == 0)
        }
    }

    @Suite("Channel Notification Settings Conflicts")
    struct ChannelNotificationSettingsConflictTests {
        @Test("Newer local toggle wins over the older server value")
        @MainActor
        func newerLocalToggleWins() async throws {
            let mapper = CloudKitSyncTests.makeMapper()
            let local = mapper.toCKRecord(channelNotificationSettings: CloudKitSyncTests.makeNotificationSettings(
                notificationsEnabled: false,
                updatedAt: Date(timeIntervalSince1970: 2_000)
            ))
            let server = mapper.toCKRecord(channelNotificationSettings: CloudKitSyncTests.makeNotificationSettings(
                notificationsEnabled: true,
                updatedAt: Date(timeIntervalSince1970: 1_000)
            ))

            let resolver = CloudKitConflictResolver()
            let resolved = await resolver.resolveChannelNotificationSettingsConflict(local: local, server: server)

            #expect(resolved["notificationsEnabled"] as? Int64 == 0)
            #expect(resolved["updatedAt"] as? Date == Date(timeIntervalSince1970: 2_000))
        }

        @Test("Newer server toggle keeps its value")
        @MainActor
        func newerServerToggleWins() async throws {
            let mapper = CloudKitSyncTests.makeMapper()
            let local = mapper.toCKRecord(channelNotificationSettings: CloudKitSyncTests.makeNotificationSettings(
                notificationsEnabled: false,
                updatedAt: Date(timeIntervalSince1970: 1_000)
            ))
            let server = mapper.toCKRecord(channelNotificationSettings: CloudKitSyncTests.makeNotificationSettings(
                notificationsEnabled: true,
                updatedAt: Date(timeIntervalSince1970: 2_000)
            ))

            let resolver = CloudKitConflictResolver()
            let resolved = await resolver.resolveChannelNotificationSettingsConflict(local: local, server: server)

            #expect(resolved["notificationsEnabled"] as? Int64 == 1)
            #expect(resolved["updatedAt"] as? Date == Date(timeIntervalSince1970: 2_000))
        }

        @Test("Equal timestamps keep the server value")
        @MainActor
        func equalTimestampsKeepServerValue() async throws {
            let mapper = CloudKitSyncTests.makeMapper()
            let stamp = Date(timeIntervalSince1970: 1_000)
            let local = mapper.toCKRecord(channelNotificationSettings: CloudKitSyncTests.makeNotificationSettings(
                notificationsEnabled: false,
                updatedAt: stamp
            ))
            let server = mapper.toCKRecord(channelNotificationSettings: CloudKitSyncTests.makeNotificationSettings(
                notificationsEnabled: true,
                updatedAt: stamp
            ))

            let resolver = CloudKitConflictResolver()
            let resolved = await resolver.resolveChannelNotificationSettingsConflict(local: local, server: server)

            #expect(resolved["notificationsEnabled"] as? Int64 == 1)
        }
    }

    // MARK: - Record Names

    @Suite("Record Names")
    struct RecordNameTests {

        private static let zone = CKRecordZone(zoneName: RecordType.zoneName)
        private static let extracted = SourceScope.from(
            sourceRawValue: "extracted", globalProvider: nil, instanceURLString: nil, externalExtractor: "media_source_webdav"
        )

        /// A WebDAV media-source ID: the full path, far past CloudKit's limit.
        private static let longVideoID = String(repeating: "Ted Lasso S04E05 Riches of Embarrassment 1080p ATVP WEB-DL/", count: 6) + "episode.mkv"

        @Test("Short IDs keep their verbatim record name")
        func shortIDVerbatim() {
            let name = SyncableRecordType.watchEntry(videoID: "abc123", scope: Self.extracted).recordID(in: Self.zone).recordName
            #expect(name == "watch-abc123@extracted:media_source_webdav")
            #expect(SyncableRecordType.isHashedBareID(SyncableRecordType.extractBareID(from: String(name.dropFirst(6)))) == false)
        }

        @Test("Over-long IDs fall back to a digest that fits CloudKit's limit")
        func longIDHashed() {
            let verbatim = "watch-\(Self.longVideoID)\(Self.extracted.recordNameSuffix)"
            #expect(verbatim.utf8.count > SyncableRecordType.maxRecordNameLength)

            let recordID = SyncableRecordType.watchEntry(videoID: Self.longVideoID, scope: Self.extracted).recordID(in: Self.zone)
            let name = recordID.recordName
            #expect(name.utf8.count <= SyncableRecordType.maxRecordNameLength)
            #expect(name.hasPrefix("watch-sha256-"))
            #expect(name.hasSuffix("@extracted:media_source_webdav"))

            let bareID = SyncableRecordType.extractBareID(from: String(name.dropFirst(6)))
            #expect(SyncableRecordType.isHashedBareID(bareID))
            #expect(SyncableRecordType.entityID(Self.longVideoID, matchesBareID: bareID))
            #expect(SyncableRecordType.entityID(Self.longVideoID + "x", matchesBareID: bareID) == false)
        }

        @Test("Digest names are stable and distinct per ID and scope")
        func digestStable() {
            let a = SyncableRecordType.bookmark(videoID: Self.longVideoID, scope: Self.extracted).recordID(in: Self.zone).recordName
            let b = SyncableRecordType.bookmark(videoID: Self.longVideoID, scope: Self.extracted).recordID(in: Self.zone).recordName
            let other = SyncableRecordType.bookmark(videoID: Self.longVideoID + "2", scope: Self.extracted).recordID(in: Self.zone).recordName
            #expect(a == b)
            #expect(a != other)
        }

        @Test("The mapper round-trips a long-ID watch entry without throwing")
        @MainActor
        func mapperLongID() {
            let entry = WatchEntry(
                videoID: Self.longVideoID,
                sourceRawValue: "extracted",
                title: "Video",
                authorName: "Channel",
                authorID: "ch1",
                duration: 10,
                watchedSeconds: 5,
                isLive: false
            )
            entry.externalExtractor = "media_source_webdav"
            let record = CloudKitSyncTests.makeMapper().toCKRecord(watchEntry: entry)
            #expect(record.recordID.recordName.hasPrefix("watch-sha256-"))
            #expect(record["videoID"] as? String == Self.longVideoID)
        }
    }
}
