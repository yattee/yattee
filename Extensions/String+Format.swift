import Foundation

extension String {
    var serializationSafe: String {
        let serializationUnsafe = ":;"
        let forbidden = CharacterSet(charactersIn: serializationUnsafe)
        let result = unicodeScalars.filter { !forbidden.contains($0) }

        return String(String.UnicodeScalarView(result))
    }
}
