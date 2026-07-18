//
//  RecentChannel.swift
//  Yattee
//
//  SwiftData model for recent channel visits.
//

import Foundation
import SwiftData

@Model
final class RecentChannel {
    var id: UUID
    var channelID: String
    var sourceRawValue: String
    var instanceURLString: String?
    var name: String
    var thumbnailURLString: String?
    var subscriberCount: Int?
    var isVerified: Bool
    var visitedAt: Date
    
    init(
        id: UUID = UUID(),
        channelID: String,
        sourceRawValue: String,
        instanceURLString: String? = nil,
        name: String,
        thumbnailURLString: String? = nil,
        subscriberCount: Int? = nil,
        isVerified: Bool = false,
        visitedAt: Date = Date()
    ) {
        self.id = id
        self.channelID = channelID
        self.sourceRawValue = sourceRawValue
        self.instanceURLString = instanceURLString
        self.name = name
        self.thumbnailURLString = thumbnailURLString
        self.subscriberCount = subscriberCount
        self.isVerified = isVerified
        self.visitedAt = visitedAt
    }
    
    /// Creates a RecentChannel from a Channel model
    static func from(channel: Channel) -> RecentChannel {
        let (sourceRaw, instanceURL) = extractSourceInfo(from: channel.id.source)
        return RecentChannel(
            channelID: channel.id.channelID,
            sourceRawValue: sourceRaw,
            instanceURLString: instanceURL,
            name: channel.name,
            thumbnailURLString: channel.thumbnailURL?.absoluteString,
            subscriberCount: channel.subscriberCount,
            isVerified: channel.isVerified
        )
    }
    
    private static func extractSourceInfo(from source: ContentSource) -> (String, String?) {
        switch source {
        case .global:
            return ("global", nil)
        case .federated(_, let instance):
            return ("federated", instance.absoluteString)
        case .extracted:
            return ("extracted", nil)
        }
    }
}
