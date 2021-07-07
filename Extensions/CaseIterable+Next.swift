extension CaseIterable where Self: Equatable {
    func next(nilAtEnd: Bool = false) -> Self! {
        let all = Self.allCases
        let index = all.firstIndex(of: self)!
        let next = all.index(after: index)

        if nilAtEnd == true {
            if next == all.endIndex {
                return nil
            }
        }

        return all[next == all.endIndex ? all.startIndex : next]
    }
}
