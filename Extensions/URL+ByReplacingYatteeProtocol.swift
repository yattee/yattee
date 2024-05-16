import Foundation

extension URL {
    func byReplacingYatteeProtocol(with urlProtocol: String = "https") -> URL! {
        var urlAbsoluteString = absoluteString

        guard urlAbsoluteString.hasPrefix(Strings.yatteeProtocol) else {
            return self
        }

        urlAbsoluteString = String(urlAbsoluteString.dropFirst(Strings.yatteeProtocol.count))
        if absoluteString.contains("://") {
            return URL(string: urlAbsoluteString)
        }

        return URL(string: "\(urlProtocol)://\(urlAbsoluteString)")
    }
}
