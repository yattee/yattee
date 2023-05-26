import Foundation

extension String {
    var replacingHTMLEntities: String {
        do {
            return try NSAttributedString(data: Data(utf8), options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ], documentAttributes: nil).string
        } catch {
            return self
        }
    }
}
