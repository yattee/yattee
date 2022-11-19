import Foundation

final class DocumentsModel: ObservableObject {
    static var shared = DocumentsModel()

    @Published private(set) var directoryURL: URL!
    @Published private(set) var refreshID = UUID()

    typealias AreInIncreasingOrder = (URL, URL) -> Bool

    init(directoryURL: URL! = nil) {
        self.directoryURL = directoryURL
    }

    private var fileManager: FileManager {
        .default
    }

    var directoryLabel: String {
        guard let directoryURL else { return "Documents" }
        return displayLabelForDocument(directoryURL)
    }

    var sortPredicates: [AreInIncreasingOrder] {
        [
            { self.isDirectory($0) && !self.isDirectory($1) },
            { $0.lastPathComponent.caseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        ]
    }

    var sortedDirectoryContents: [URL] {
        directoryContents.sorted { lhs, rhs in
            for predicate in sortPredicates {
                if !predicate(lhs, rhs), !predicate(rhs, lhs) {
                    continue
                }

                return predicate(lhs, rhs)
            }

            return false
        }
    }

    var directoryContents: [URL] {
        guard let directoryURL else { return [] }
        return contents(of: directoryURL)
    }

    var documentsDirectory: URL? {
        if let url = try? fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            return replacePrivateVar(url)
        }
        return nil
    }

    func recentDocuments(_ limit: Int = 10) -> [URL] {
        guard let documentsDirectory else { return [] }

        return Array(
            contents(of: documentsDirectory)
                .filter { !isDirectory($0) }
                .sorted {
                    ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()) >
                        ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date())
                }
                .prefix(limit)
        )
    }

    func isDocument(_ video: Video) -> Bool {
        guard video.isLocal, let url = video.localStream?.localURL, let url = replacePrivateVar(url) else { return false }
        return isDocument(url)
    }

    func isDocument(_ url: URL) -> Bool {
        guard let url = replacePrivateVar(url), let documentsDirectory else { return false }
        return url.absoluteString.starts(with: documentsDirectory.absoluteString)
    }

    func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    var creationDateFormatter: DateFormatter {
        let formatter = DateFormatter()

        formatter.setLocalizedDateFormatFromTemplate("YYMMddHHmm")

        return formatter
    }

    func creationDate(_ video: Video) -> Date? {
        guard video.isLocal, let url = video.localStream?.localURL, let url = replacePrivateVar(url) else { return nil }
        return creationDate(url)
    }

    func creationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
    }

    func formattedCreationDate(_ video: Video) -> String? {
        guard video.isLocal, let url = video.localStream?.localURL, let url = replacePrivateVar(url) else { return nil }
        return formattedCreationDate(url)
    }

    func formattedCreationDate(_ url: URL) -> String? {
        if let date = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate {
            return creationDateFormatter.string(from: date)
        }

        return nil
    }

    var sizeFormatter: ByteCountFormatter {
        let formatter = ByteCountFormatter()

        formatter.allowedUnits = .useAll
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true

        return formatter
    }

    func size(_ video: Video) -> Int? {
        guard video.isLocal, let url = video.localStream?.localURL, let url = replacePrivateVar(url) else { return nil }
        return size(url)
    }

    func size(_ url: URL) -> Int? {
        try? url.resourceValues(forKeys: [.fileAllocatedSizeKey]).fileAllocatedSize
    }

    func formattedSize(_ video: Video) -> String? {
        guard let size = size(video) else { return nil }
        return sizeFormatter.string(fromByteCount: Int64(size))
    }

    func formattedSize(_ url: URL) -> String? {
        guard let size = size(url) else { return nil }
        return sizeFormatter.string(fromByteCount: Int64(size))
    }

    func removeDocument(_ url: URL) throws {
        guard isDocument(url) else { return }
        try fileManager.removeItem(at: url)
        URLBookmarkModel.shared.removeBookmark(url)
        refresh()
    }

    private func contents(of directory: URL) -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey, .fileAllocatedSizeKey, .isDirectoryKey],
            options: [.includesDirectoriesPostOrder, .skipsHiddenFiles]
        )) ?? []
    }

    private func displayLabelForDocument(_ file: URL) -> String {
        let components = file.absoluteString.components(separatedBy: "/Documents/")
        if components.count == 2 {
            let component = components[1]
            return component.isEmpty ? "Documents" : component.removingPercentEncoding ?? component
        }
        return "Document"
    }

    var canGoBack: Bool {
        guard let directoryURL, let documentsDirectory else { return false }
        return replacePrivateVar(directoryURL) != documentsDirectory
    }

    func goToURL(_ url: URL) {
        directoryURL = url
    }

    func goBack() {
        directoryURL = urlToGoBack
    }

    func goToTop() {
        directoryURL = documentsDirectory
    }

    private var urlToGoBack: URL? {
        directoryURL?.deletingLastPathComponent()
    }

    func replacePrivateVar(_ url: URL) -> URL? {
        let urlStringWithPrivateVarRemoved = url.absoluteString.replacingFirstOccurrence(of: "/private/var/", with: "/var/")
        return URL(string: urlStringWithPrivateVarRemoved)
    }

    func refresh() {
        refreshID = UUID()
    }
}
