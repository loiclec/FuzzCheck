
// I didn't want to implement my own random number generator, but I didn't
// find a single one that can be seeded manually. Send help plz.

public struct FuzzerPRNG: RandomNumberGenerator {
    
    public var seed: UInt32
    
    public init(seed: UInt32) {
        self.seed = seed
    }
    
    private mutating func next31() -> UInt32 {
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
    
    public mutating func weightedRandomElement <T, W> (from c: [(T, W)], minimum: W) -> T where W: RandomRangeInitializable {
        precondition(!c.isEmpty)
        return c.withUnsafeBufferPointer { b in
            var i = b.baseAddress.unsafelyUnwrapped
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
    
    public mutating func bool(odds: Double) -> Bool {
        precondition(0 < odds && odds < 1)
        let x = Double.random(in: 0 ..< 1, using: &self)
        return x < odds
    }
}


extension FuzzerPRNG {
    mutating func shuffle <C> (_ c: inout C) where C: MutableCollection, C: RandomAccessCollection, C.Index: RandomRangeInitializable {
        for i in c.indices.reversed() {
            c.swapAt(C.Index.random(in: c.startIndex ..< c.index(after: i), using: &self), i)
        }
    }
}

extension Sequence {
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

extension BinarySearchOrdering {
    public var opposite: BinarySearchOrdering {
        switch self {
        case .less:
            return .greater
        case .match:
            return .match
        case .greater:
            return .less
        }
    }
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
