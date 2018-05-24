
struct FixedSizeArray <T>: Sequence {
    let count: Int
    var array: [T]

    init(repeating: T, count: Int) {
        self.count = count
        self.array = Array(repeating: repeating, count: count)
    }
    
    mutating func reset(to filler: T) {
        array.replaceSubrange(array.indices, with: repeatElement(filler, count: count))
    }
    
    func makeIterator() -> IndexingIterator<[T]> {
        return array.makeIterator()
    }
    var indices: CountableRange<Int> { return 0 ..< count }
}
