import Foundation

extension String {
    func localized(_ comment: String = "") -> Self {
        NSLocalizedString(self, tableName: "Localizable", bundle: .main, comment: comment)
    }
}
