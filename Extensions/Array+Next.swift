extension Array where Element: Equatable {
    func next(after element: Element) -> Element? {
        let idx = firstIndex(of: element)

        if idx.isNil {
            return first
        }

        let next = index(after: idx!)

        return self[next == endIndex ? startIndex : next]
    }
}
