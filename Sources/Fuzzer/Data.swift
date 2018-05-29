//
//  Data.swift
//  Fuzzer
//
//  Created by Loïc Lecrenier on 27/05/2018.
//

public struct Complexity {
    public var value: Double
}
extension Complexity {
    public init(_ v: Double) {
        self.value = v
    }
}
extension Complexity: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self.value = value
    }
}
extension Complexity: Hashable {}
extension Complexity: Comparable {
    public static func < (lhs: Complexity, rhs: Complexity) -> Bool {
        return lhs.value < rhs.value
    }
    public static func <= (lhs: Complexity, rhs: Complexity) -> Bool {
        return lhs.value <= rhs.value
    }
    public static func > (lhs: Complexity, rhs: Complexity) -> Bool {
        return lhs.value > rhs.value
    }
    public static func >= (lhs: Complexity, rhs: Complexity) -> Bool {
        return lhs.value >= rhs.value
    }
}
extension Complexity: CustomStringConvertible {
    public var description: String {
        return value.description
    }
}


struct Feature {
    struct Key {
        var k: Int
    }
    let key: Key
    let coverage: Coverage

    enum Coverage {
        case pc
        case valueProfile
        //case newComparison
        //case redundantComparison
    }
}

extension Feature.Key: Hashable, Comparable {
    var hashValue: Int {
        return k.hashValue
    }
    static func == (lhs: Feature.Key, rhs: Feature.Key) -> Bool {
        return lhs.k == rhs.k
    }
}

extension Feature.Key: Strideable {
    typealias Stride = Int
    
    func distance(to other: Feature.Key) -> Int {
        return k.distance(to: other.k)
    }
    
    func advanced(by n: Int) -> Feature.Key {
        return .init(k: k.advanced(by: n))
    }
}

extension Feature.Coverage {

    struct Score {
        var s: Int
        init(_ s: Int) { self.s = s }
    }

    var importance: Score {
        switch self {
        case .pc:
            return .init(1)
        case .valueProfile:
            return .init(1)
        }
    }
}
extension Feature.Coverage.Score: ExpressibleByIntegerLiteral {
    init(integerLiteral value: Int) {
        self.s = value
    }
}
extension Feature.Coverage.Score: Comparable {
    static func < (lhs: Feature.Coverage.Score, rhs: Feature.Coverage.Score) -> Bool {
        return lhs.s < rhs.s
    }
    static func <= (lhs: Feature.Coverage.Score, rhs: Feature.Coverage.Score) -> Bool {
        return lhs.s <= rhs.s
    }
    static func > (lhs: Feature.Coverage.Score, rhs: Feature.Coverage.Score) -> Bool {
        return lhs.s > rhs.s
    }
    static func >= (lhs: Feature.Coverage.Score, rhs: Feature.Coverage.Score) -> Bool {
        return lhs.s >= rhs.s
    }
    static func == (lhs: Feature.Coverage.Score, rhs: Feature.Coverage.Score) -> Bool {
        return lhs.s == rhs.s
    }
    static func != (lhs: Feature.Coverage.Score, rhs: Feature.Coverage.Score) -> Bool {
        return lhs.s != rhs.s
    }
}
extension Feature.Coverage.Score: CustomStringConvertible {
    var description: String { return s.description }
}

typealias FeatureDictionary = UnsafeMutableBufferPointer<(Complexity, CorpusIndex)?>

extension UnsafeMutableBufferPointer where Element == (Complexity, CorpusIndex)? {
    static func createEmpty() -> UnsafeMutableBufferPointer {
        return UnsafeMutableBufferPointer.allocateAndInitializeTo(nil, capacity: 1 << 21)
    }
    subscript(idx: Feature.Key) -> (Complexity, CorpusIndex)? {
        get {
            return self[idx.k % count]
        }
        set {
            self[idx.k % count] = newValue
        }
    }
}





