import Foundation

extension String {
    func replacingFirstOccurrence(of target: String, with replacement: String) -> String {
        guard let range = range(of: target) else {
            return self
        }
        return replacingCharacters(in: range, with: replacement)
    }
}
