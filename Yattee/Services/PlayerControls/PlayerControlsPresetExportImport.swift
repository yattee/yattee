//
//  PlayerControlsPresetExportImport.swift
//  Yattee
//
//  Service for importing and exporting player controls presets to JSON files.
//

import Foundation

// MARK: - Import Errors

/// Errors that can occur when importing a player controls preset.
enum LayoutPresetImportError: LocalizedError, Equatable, Sendable {
    /// The file contains invalid or corrupted data.
    case invalidData

    /// The file is empty.
    case emptyFile

    /// JSON parsing failed with a specific error.
    case parsingFailed(String)

    /// The preset was created for a different device class.
    case wrongDeviceClass(expected: DeviceClass, found: DeviceClass)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return String(localized: "settings.playerControls.import.error.invalidData")
        case .emptyFile:
            return String(localized: "settings.playerControls.import.error.emptyFile")
        case .parsingFailed(let details):
            return String(localized: "settings.playerControls.import.error.parsingFailed \(details)")
        case .wrongDeviceClass(_, let found):
            return String(localized: "settings.playerControls.import.error.wrongDeviceClass \(found.displayName)")
        }
    }
}

// MARK: - Export/Import Service

/// Service for importing and exporting player controls presets.
enum PlayerControlsPresetExportImport {
    // MARK: - Export

    /// Exports a preset to pretty-printed JSON data.
    /// - Parameter preset: The preset to export.
    /// - Returns: JSON data, or nil if encoding failed.
    static func exportToJSON(_ preset: LayoutPreset) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            return try encoder.encode(preset)
        } catch {
            LoggingService.shared.error(
                "Failed to encode preset to JSON: \(error.localizedDescription)",
                category: .general
            )
            return nil
        }
    }

    /// Generates an export filename for a preset.
    /// Format: yattee-preset-{sanitized-name}-{date}.json
    /// - Parameter preset: The preset to generate a filename for.
    /// - Returns: A filename string.
    static func generateExportFilename(for preset: LayoutPreset) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())

        // Sanitize name for filename (remove special characters, limit length)
        let sanitizedName = preset.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined()
            .prefix(20)

        return "yattee-preset-\(sanitizedName)-\(dateString).json"
    }

    // MARK: - Import

    /// Imports a preset from JSON data.
    ///
    /// Validates that the preset's device class matches the current device.
    /// The imported preset will have:
    /// - A new UUID (to avoid conflicts)
    /// - `isBuiltIn` set to false
    /// - `createdAt` and `updatedAt` set to now
    ///
    /// - Parameter data: JSON data to parse.
    /// - Returns: A new `LayoutPreset` ready to be saved.
    /// - Throws: `LayoutPresetImportError` if parsing or validation fails.
    static func importFromJSON(_ data: Data) throws -> LayoutPreset {
        guard !data.isEmpty else {
            throw LayoutPresetImportError.emptyFile
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let importedPreset: LayoutPreset
        do {
            importedPreset = try decoder.decode(LayoutPreset.self, from: data)
        } catch let decodingError as DecodingError {
            let details = describeDecodingError(decodingError)
            throw LayoutPresetImportError.parsingFailed(details)
        } catch {
            throw LayoutPresetImportError.invalidData
        }

        // Validate device class matches current device
        let currentDeviceClass = DeviceClass.current
        guard importedPreset.deviceClass == currentDeviceClass else {
            throw LayoutPresetImportError.wrongDeviceClass(
                expected: currentDeviceClass,
                found: importedPreset.deviceClass
            )
        }

        // Create a new preset with regenerated metadata
        let now = Date()
        return LayoutPreset(
            id: UUID(),
            name: importedPreset.name,
            createdAt: now,
            updatedAt: now,
            isBuiltIn: false,
            deviceClass: currentDeviceClass,
            layout: importedPreset.layout
        )
    }

    // MARK: - Private Helpers

    /// Provides a human-readable description of a decoding error.
    private static func describeDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Type mismatch for \(type) at \(path)"
        case .valueNotFound(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Missing value of type \(type) at \(path)"
        case .keyNotFound(let key, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Missing key '\(key.stringValue)' at \(path)"
        case .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return error.localizedDescription
        }
    }
}
