import Defaults
import Foundation

struct QualityProfile: Hashable, Identifiable, Defaults.Serializable {
    static var bridge = QualityProfileBridge()
    static var defaultProfile = Self(id: "default", backend: .mpv, resolution: .hd720p60, formats: [.stream], order: Array(Format.allCases.indices))

    enum Format: String, CaseIterable, Identifiable, Defaults.Serializable {
        case avc1
        case stream
        case webm
        case mp4
        case av1
        case hls

        var id: String {
            rawValue
        }

        var description: String {
            switch self {
            case .stream:
                return "Stream"
            case .webm:
                return "WebM"
            default:
                return rawValue.uppercased()
            }
        }

        var streamFormat: Stream.Format? {
            switch self {
            case .avc1:
                return .avc1
            case .stream:
                return nil
            case .webm:
                return .webm
            case .mp4:
                return .mp4
            case .av1:
                return .av1
            case .hls:
                return nil
            }
        }
    }

    var id = UUID().uuidString

    var name: String?
    var backend: PlayerBackendType
    var resolution: ResolutionSetting
    var formats: [Format]
    var order: [Int]
    var description: String {
        if let name, !name.isEmpty { return name }
        return "\(backend.label) - \(resolution.description) - \(formatsDescription)"
    }

    var formatsDescription: String {
        switch formats.count {
        case Format.allCases.count:
            return "Any format".localized()
        case 0:
            return "No format selected".localized()
        case 1 ... 3:
            return formats.map(\.description).joined(separator: ", ")
        default:
            return String(format: "%@ formats".localized(), String(formats.count))
        }
    }

    func isPreferred(_ stream: Stream) -> Bool {
        if formats.contains(.hls), stream.kind == .hls {
            return true
        }

        let defaultResolution = Stream.Resolution.custom(height: 720, refreshRate: 30)
        let resolutionMatch = resolution.value ?? defaultResolution >= stream.resolution

        if resolutionMatch, formats.contains(.stream), stream.kind == .stream {
            return true
        }

        let formatMatch = formats.compactMap(\.streamFormat).contains(stream.format)

        return resolutionMatch && formatMatch
    }
}

struct QualityProfileBridge: Defaults.Bridge {
    static let formatsSeparator = ","

    typealias Value = QualityProfile
    typealias Serializable = [String: String]

    func serialize(_ value: Value?) -> Serializable? {
        guard let value else { return nil }

        return [
            "id": value.id,
            "name": value.name ?? "",
            "backend": value.backend.rawValue,
            "resolution": value.resolution.rawValue,
            "formats": value.formats.map(\.rawValue).joined(separator: Self.formatsSeparator),
            "order": value.order.map { String($0) }.joined(separator: Self.formatsSeparator) // New line
        ]
    }

    func deserialize(_ object: Serializable?) -> Value? {
        guard let object,
              let id = object["id"],
              let backend = PlayerBackendType(rawValue: object["backend"] ?? ""),
              let resolution = ResolutionSetting(rawValue: object["resolution"] ?? "")
        else {
            return nil
        }

        let name = object["name"]
        let formats = (object["formats"] ?? "").components(separatedBy: Self.formatsSeparator).compactMap { QualityProfile.Format(rawValue: $0) }
        let order = (object["order"] ?? "").components(separatedBy: Self.formatsSeparator).compactMap { Int($0) }

        return .init(id: id, name: name, backend: backend, resolution: resolution, formats: formats, order: order)
    }
}
