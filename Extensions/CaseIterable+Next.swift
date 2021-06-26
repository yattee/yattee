extension CaseIterable where Self: Equatable {
    func next() -> Self {
        let all = Self.allCases
        let index = all.firstIndex(of: self)!
        let next = all.index(after: index)
        return all[next == all.endIndex ? all.startIndex : next]
    }
}
