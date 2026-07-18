//
//  UnifiedSource.swift
//  Yattee
//
//  Unified wrapper for Instance and MediaSource types for display in the Sources settings.
//

import Foundation

/// Represents any source type for unified display in the Sources list.
enum UnifiedSource: Identifiable, Hashable, Sendable {
    case remoteServer(Instance)
    case fileSource(MediaSource)

    // MARK: - Identifiable

    var id: UUID {
        switch self {
        case .remoteServer(let instance):
            return instance.id
        case .fileSource(let source):
            return source.id
        }
    }

    // MARK: - Common Properties

    var name: String {
        switch self {
        case .remoteServer(let instance):
            return instance.displayName
        case .fileSource(let source):
            return source.name
        }
    }

    var isEnabled: Bool {
        switch self {
        case .remoteServer(let instance):
            return instance.isEnabled
        case .fileSource(let source):
            return source.isEnabled
        }
    }

    var urlDisplayString: String {
        switch self {
        case .remoteServer(let instance):
            return instance.url.host ?? instance.url.absoluteString
        case .fileSource(let source):
            return source.urlDisplayString
        }
    }
}
