extension Array where Element: Hashable {
    /// Elements in their original order with duplicates removed.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
