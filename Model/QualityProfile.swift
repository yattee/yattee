import Defaults
import Foundation

struct QualityProfile: Hashable, Identifiable, Defaults.Serializable {
    static var bridge = QualityProfileBridge()
    static var defaultProfile = Self(id: "default", backend: .mpv, resolution: .hd720p60, formats: [.stream], order: Array(Format.allCases.indices))

    enum Format: String, CaseIterable, Identifiable, Defaults.Serializable {
        case hls
        case stream
        case avc1
        case mp4
        case av1
        case webm

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
            case .hls:
                return nil
            case .stream:
                return nil
            case .avc1:
                return .avc1
            case .mp4:
                return .mp4
            case .av1:
                return .av1
            case .webm:
                return .webm
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
        if formats.count == Format.allCases.count {
            return "Any format".localized()
        }
        if formats.count <= 3 {
            return formats.map(\.description).joined(separator: ", ")
        }

        return String(format: "%@ formats".localized(), String(formats.count))
    }

    func isPreferred(_ stream: Stream) -> Bool {
        if formats.contains(.hls), stream.kind == .hls {
            return true
        }

        let resolutionMatch = !stream.resolution.isNil && resolution.value >= stream.resolution

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
            "formats": value.formats.map { $0.rawValue }.joined(separator: Self.formatsSeparator),
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
