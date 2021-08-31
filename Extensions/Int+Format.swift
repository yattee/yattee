import Foundation

extension Int {
    func formattedAsAbbreviation() -> String {
        typealias Abbrevation = (threshold: Double, divisor: Double, suffix: String)
        let abbreviations: [Abbrevation] = [
            (0, 1, ""), (1000.0, 1000.0, "K"),
            (999_999.0, 1_000_000.0, "M"), (999_999_999.0, 1_000_000_000.0, "B")
        ]

        let startValue = Double(abs(self))

        guard let nextAbbreviationIndex = abbreviations.firstIndex(where: { startValue < $0.threshold }) else {
            return String(self)
        }

        let abbreviation = abbreviations[abbreviations.index(before: nextAbbreviationIndex)]
        let formatter = NumberFormatter()

        formatter.positiveSuffix = abbreviation.suffix
        formatter.negativeSuffix = abbreviation.suffix
        formatter.allowsFloats = true
        formatter.minimumIntegerDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1

        return formatter.string(from: NSNumber(value: Double(self) / abbreviation.divisor))!
    }
}
