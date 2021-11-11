import Foundation

extension Int {
    func formattedAsAbbreviation() -> String {
        let num = fabs(Double(self))

        guard num >= 1000.0 else {
            return String(self)
        }

        let exp = Int(log10(num) / 3.0)
        let units = ["K", "M", "B", "T", "X"]
        let unit = units[exp - 1]

        let formatter = NumberFormatter()

        formatter.positiveSuffix = unit
        formatter.negativeSuffix = unit
        formatter.allowsFloats = true
        formatter.minimumIntegerDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1

        let roundedNum = round(10 * num / pow(1000.0, Double(exp))) / 10
        return formatter.string(from: NSNumber(value: roundedNum))!
    }
}
