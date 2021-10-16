extension Array where Element: Equatable {
    func next(after element: Element?) -> Element? {
        if element.isNil {
            return first
        }

        let idx = firstIndex(of: element!)

        if idx.isNil {
            return first
        }

        let next = index(after: idx!)

        return self[next == endIndex ? startIndex : next]
    }
}
