
// I didn't want to implement my own random number generator, but I didn't
// find a single one that can be seeded manually. Send help plz.

/// A pseudo-random number generator that can be seeded
public struct FuzzerPRNG: RandomNumberGenerator {
    
    public var seed: UInt32
    
    public init(seed: UInt32) {
        self.seed = seed
    }
    
    /// Return an integer whose 31 lower bits are pseudo-random
    private mutating func next31() -> UInt32 {
        // https://software.intel.com/en-us/articles/fast-random-number-generator-on-the-intel-pentiumr-4-processor/
        seed = 214013 &* seed &+ 2531011
        return seed >> 16 &* 0x7FFF
    }
}

extension FuzzerPRNG {
    public mutating func next() -> UInt16 {
        return UInt16(next31() & 0xFFFF)
    }
    
    public mutating func next() -> UInt32 {
        let l = next() as UInt16
        let r = next() as UInt16
        return (UInt32(l) << 16) | UInt32(r)
    }
    
    public mutating func next() -> UInt64 {
        let l = next() as UInt32
        let r = next() as UInt32
        return (UInt64(l) << 32) | UInt64(r)
    }
}

extension RandomNumberGenerator {
    /**
     Pick a random index from the `cumulativeWeights` collection where the probability of
     choosing an index is given by the distance between `cumulativeWeights[i]` and its
     predecessor.
     
     To be more precise, for a collection `c`, each index has a probability
     `(c[i] - c[i-1]) / (max(c) - minimum)` of being chosen, where `c[-1] = minimum`.
     
     ## Example
     ```
     let xs = [2, 4, 8, 9]
     let idx = weightedRandomIndex(cumulativeWeights: xs, minimum: 1)
     
     idx is:
     - i with probability (xs[i] - xs[i-1]) / (max(xs) - minimum)
     - 0 with probability (2 - 1) / 8 == 1/8
     - 1 with probability (4 - 2) / 8 == 2/8
     - 2 with probability (8 - 4) / 8 == 4/8
     - 3 with probability (9 - 8) / 8 == 1/8
     ```
     
     - Precondition:
       - `cumulativeWeights` is sorted
       - `minimum` <= min(cumulativeWeights)
    
     - Complexity: O(log(n)) with n = cumulativeWeights.count
    */
    public mutating func weightedRandomIndex <W: RandomAccessCollection> (cumulativeWeights: W, minimum: W.Element) -> W.Index where W.Element: RandomRangeInitializable {

        let randWeight = W.Element.random(in: minimum ..< cumulativeWeights.last!, using: &self)
        var index: W.Index = cumulativeWeights.startIndex
        switch cumulativeWeights.binarySearch(compare: { $0.compare(randWeight) }) {
        case .success(let i):
            index = min(cumulativeWeights.index(before: cumulativeWeights.endIndex), cumulativeWeights.index(after: i))
        case .failure(_, let end):
            index = min(cumulativeWeights.index(before: cumulativeWeights.endIndex), end)
        }
        while index > cumulativeWeights.startIndex {
            let before = cumulativeWeights.index(before: index)
            if cumulativeWeights[before] == cumulativeWeights[index] {
                index = before
            } else {
                break
            }
        }
        return index
    }
    
    /**
     Pick a random index from the given collection using the same policy as
     `weightedRandomIndex`, and return `c[idx].0`. Unlike `weightedRandomIndex`,
     this method runs in O(c.count) time.
     
     Prefer using this method over `weightedRandomIndex` when the collection is expected
     to be very small and performance is important.
     
     ## Example
     ```
     let xs = [("a", 2), ("b", 4), ("c", 8), ("d", 9)]
     let element = weightedRandomElement(from: xs, minimum: 1)
     
     element is:
     - "a" with probability (2 - 1) / 8 == 1/8
     - "b" with probability (4 - 2) / 8 == 2/8
     - "c" with probability (8 - 4) / 8 == 4/8
     - "d" with probability (9 - 8) / 8 == 1/8
     ```
     
     - Precondition:
       Let w be c.map{$0.1}.
       - `w` is sorted
       - `minimum` <= min(w)
     
     - Complexity: O(n) with `n = c.count`
    */
    public mutating func weightedRandomElement <T, W> (from c: [(T, W)], minimum: W) -> T where W: RandomRangeInitializable {
        precondition(!c.isEmpty)
        // inelegant, but I needed that one to be fast
        return c.withUnsafeBufferPointer { b in
            var i = b.baseAddress!
            let randWeight = W.random(in: minimum ..< i.advanced(by: (b.count &- 1)).pointee.1, using: &self)
            let last = i.advanced(by: b.count)
            while i < last {
                if i.pointee.1 > randWeight {
                    return i.pointee.0
                }
                i = i.advanced(by: 1)
            }
            fatalError()
        }
    }
    
    /// Return true with probability `odds` (e.g. odds = 0.33 -> will return true 1/3rd of the time)
    public mutating func bool(odds: Double) -> Bool {
        precondition(0 < odds && odds < 1)
        let x = Double.random(in: 0 ..< 1, using: &self)
        return x < odds
    }
}

extension Sequence {
    /**
     Return an array whose elements are given by `self.prefix(i+1).reduce(initial, acc)`
     with `i` being the index of the element.
     
     ## Example
     ```
     let xs = [1, 0, 9, -1, 3]
     let sums = xs.scan(2, +)
     // sums == [3, 3, 12, 11, 14]
     ```
    */
    public func scan <T> (_ initial: T, _ acc: (T, Element) -> T) -> [T] {
        var results: [T] = []
        var t = initial
        for x in self {
            t = acc(t, x)
            results.append(t)
        }
        return results
    }
}

public enum BinarySearchOrdering {
    case less
    case match
    case greater
}

extension RandomAccessCollection {
    public func binarySearch(compare: (Element) -> BinarySearchOrdering) -> BinarySearchResult<Index> {
        var beforeBound = startIndex
        var startSearch = startIndex
        var endSearch = endIndex
        
        while startSearch != endSearch {
            let mid = self.index(startSearch, offsetBy: distance(from: startSearch, to: endSearch) / 2)
            let candidate = self[mid]
            switch compare(candidate) {
            case .less:
                beforeBound = mid
                startSearch = index(after: mid)
            case .match:
                return .success(mid)
            case .greater:
                endSearch = mid
            }
        }
        return .failure(start: beforeBound, end: endSearch)
    }
}

public enum BinarySearchResult <Index> {
    case success(Index)
    case failure(start: Index, end: Index)
}

extension Comparable {
    public func compare(_ element: Self) -> BinarySearchOrdering {
        if self > element { return .greater }
        else if self < element { return .less }
        else { return .match }
    }
}

public protocol RandomInitializable {
    static func random <R: RandomNumberGenerator> (using r: inout R) -> Self
}
public protocol RandomRangeInitializable : Comparable {
    static func random <R: RandomNumberGenerator> (in range: Range<Self>, using r: inout R) -> Self
}

extension FixedWidthInteger where Self: UnsignedInteger {
    public static func random <R: RandomNumberGenerator> (using r: inout R) -> Self {
        return r.next()
    }
}

extension UInt8: RandomInitializable, RandomRangeInitializable {}
extension UInt16: RandomInitializable, RandomRangeInitializable {}
extension UInt32: RandomInitializable, RandomRangeInitializable {}
extension UInt64: RandomInitializable, RandomRangeInitializable {}
extension UInt: RandomInitializable, RandomRangeInitializable {}

extension Int8: RandomInitializable, RandomRangeInitializable {
    public static func random <R: RandomNumberGenerator> (using r: inout R) -> Int8 {
        return .init(bitPattern: r.next())
    }
}
extension Int16: RandomInitializable, RandomRangeInitializable {
    public static func random <R: RandomNumberGenerator> (using r: inout R) -> Int16 {
        return .init(bitPattern: r.next())
    }
}
extension Int32: RandomInitializable, RandomRangeInitializable {
    public static func random <R: RandomNumberGenerator> (using r: inout R) -> Int32 {
        return .init(bitPattern: r.next())
    }
}
extension Int64: RandomInitializable, RandomRangeInitializable {
    public static func random <R: RandomNumberGenerator> (using r: inout R) -> Int64 {
        return .init(bitPattern: r.next())
    }
}
extension Int: RandomInitializable, RandomRangeInitializable {
    public static func random <R: RandomNumberGenerator> (using r: inout R) -> Int {
        return .init(bitPattern: r.next())
    }
}
extension Float: RandomRangeInitializable { }
extension Double: RandomRangeInitializable { }
extension Float80: RandomRangeInitializable { }

extension Bool: RandomInitializable { }
