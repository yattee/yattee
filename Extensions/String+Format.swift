import Foundation

extension String {
    func replacingFirstOccurrence(of target: String, with replacement: String) -> String {
        guard let range = range(of: target) else {
            return self
        }
        return replacingCharacters(in: range, with: replacement)
    }

    func replacingMatches(regex: String, replacementStringClosure: (String) -> String?) -> String {
        guard let regex = try? NSRegularExpression(pattern: regex) else {
            return self
        }

        let results = regex.matches(in: self, range: NSRange(startIndex..., in: self))

        var outputText = self

        for match in results.reversed() {
            for rangeIndex in (1 ..< match.numberOfRanges).reversed() {
                let matchingGroup: String = (self as NSString).substring(with: match.range(at: rangeIndex))
                let rangeBounds = match.range(at: rangeIndex)

                guard let range = Range(rangeBounds, in: self) else {
                    continue
                }
                let replacement = replacementStringClosure(matchingGroup) ?? matchingGroup

                outputText = outputText.replacingOccurrences(of: matchingGroup, with: replacement, range: range)
            }
        }
        return outputText
    }
}
