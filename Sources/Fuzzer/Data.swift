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
    private let lowerBits: UInt16 // all 16 bits are used, they are part of the key
    private let upperBits: UInt16 // 5 bits are used for the key, and one bit for the coverage
    
    var key: Key {
        return Key.init(k: (Int(upperBits & 0b11111) << 16) | Int(lowerBits))
    }
    var coverage: Coverage {
        if (upperBits & 0b100000) == 0b100000 {
            return .valueProfile
        } else {
            return .pc
        }
    }
    init(key: Key, coverage: Coverage) {
        self.lowerBits = UInt16(key.k & 0xffff) // store the lower 16 bits of the key
        // store the bit for the coverage at position 6 and the remaining 5 bits of the key
        self.upperBits = UInt16(Int(coverage.rawValue << 6) | (key.k >> 16)) // this will fail if the key used more than 21 bits
    }
    
    struct Key {
        var k: Int // 21 bits
    }
    /*
    let key: Key
    let coverage: Coverage // 1 bit
     */
    enum Coverage: UInt8 {
        case pc = 0
        case valueProfile = 1
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
            return (self.baseAddress.unsafelyUnwrapped + idx.k).pointee// .pointee [idx.k/* % count*/]
        }
        set {
            (self.baseAddress.unsafelyUnwrapped + idx.k).pointee = newValue//self[idx.k/* % count*/] = newValue
        }
    }
}





