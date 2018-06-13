//
//  Data.swift
//  Fuzzer
//
//  Created by Loïc Lecrenier on 27/05/2018.
//

public struct Complexity: Codable {
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


public struct Feature: Equatable, Hashable {
    static let keyLengthInBits = 24
    
    static let keyMask: UInt32      = 0x00_ffffff // 24 lower bits
    static let coverageMask: UInt32 = 0xff_000000 // 8 upper bits
    
    fileprivate var bits: UInt32
    
    fileprivate init(bits: UInt32) {
        self.bits = bits
    }
    /*
     The lower 24 bits are meant to index wither the eightBitCounters array or the valueProfileMap.
     The eightBitCounters array has a maximum size of 2^21, and each counter can each have up to 8 associated features,
     hence 24 bits are used to uniquely index a feature associated with a counter
     The valueProfileMap is smaller than the eightBitCounters.
     
     The upper 8 bits are there to distinguish between the coverage kind of the feature. Currently, only 1 but is used to distinguish between pc and valueProfile
    */
    
    var key: UInt32 {
        // take the lower 24 bits
        get {
            return bits & Feature.keyMask
        }
        set {
            bits &= ~Feature.keyMask // reset bits of key
            bits |= newValue & Feature.keyMask
        }
    }
    var coverage: Coverage {
        get {
            let rawValue = UInt8(bits >> Feature.keyLengthInBits)
            return Coverage(rawValue: rawValue)!
        }
        set {
            bits &= Feature.keyMask // reset bits of coverage
            bits |= UInt32(newValue.rawValue) << Feature.keyLengthInBits
        }
    }
    
    init(key: UInt32, coverage: Coverage) {
        self.bits = (key & Feature.keyMask) | (UInt32(coverage.rawValue) << Feature.keyLengthInBits)
    }
    
    public enum Coverage: UInt8 {
        case pc = 0
        case valueProfile = 1
    }
}

extension Feature {
    static func &+ (lhs: Feature, rhs: UInt32) -> Feature {
        return Feature(bits: lhs.bits &+ rhs)
    }
}

extension Feature.Coverage: Codable {
    
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .pc:
            try "pc".encode(to: encoder)
        case .valueProfile:
            try "value-profile".encode(to: encoder)
        }
    }
    public init(from decoder: Decoder) throws {
        let s = try String.init(from: decoder)
        switch s {
        case "pc":
            self = .pc
        case "value-profile":
            self = .valueProfile
        default:
            throw DecodingError.valueNotFound(Feature.Coverage.self, DecodingError.Context(codingPath: [], debugDescription: "Expected to find either “pc” or “value-profile”"))
        }
    }
}

extension Feature: Codable {
    
    enum CodingKey: Swift.CodingKey {
        case kind
        case key
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKey.self)
        try container.encode(coverage, forKey: .kind)
        try container.encode(key, forKey: .key)
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKey.self)
        let coverage = try container.decode(Coverage.self, forKey: .kind)
        let key =  try container.decode(UInt32.self, forKey: .key)
        self.init(bits: 0)
        self.coverage = coverage
        self.key = key
    }
}

extension Feature.Coverage {

    public struct Score: Hashable, Codable {
        var value: Int
        init(_ s: Int) { self.value = s }
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
    public init(integerLiteral value: Int) {
        self.value = value
    }
}

extension Feature.Coverage.Score {
    static func + (lhs: Feature.Coverage.Score, rhs: Feature.Coverage.Score) -> Feature.Coverage.Score {
        return Feature.Coverage.Score(lhs.value + rhs.value)
    }
}

extension Feature.Coverage.Score: Comparable {
    public static func < (lhs: Feature.Coverage.Score, rhs: Feature.Coverage.Score) -> Bool {
        return lhs.value < rhs.value
    }
    public static func <= (lhs: Feature.Coverage.Score, rhs: Feature.Coverage.Score) -> Bool {
        return lhs.value <= rhs.value
    }
    public static func > (lhs: Feature.Coverage.Score, rhs: Feature.Coverage.Score) -> Bool {
        return lhs.value > rhs.value
    }
    public static func >= (lhs: Feature.Coverage.Score, rhs: Feature.Coverage.Score) -> Bool {
        return lhs.value >= rhs.value
    }
    public static func == (lhs: Feature.Coverage.Score, rhs: Feature.Coverage.Score) -> Bool {
        return lhs.value == rhs.value
    }
    public static func != (lhs: Feature.Coverage.Score, rhs: Feature.Coverage.Score) -> Bool {
        return lhs.value != rhs.value
    }
}
extension Feature.Coverage.Score: CustomStringConvertible {
    public var description: String { return value.description }
}

typealias FeatureDictionary = UnsafeMutableBufferPointer<(Complexity, CorpusIndex)?>

extension UnsafeMutableBufferPointer where Element == (Complexity, CorpusIndex)? {
    static func createEmpty() -> UnsafeMutableBufferPointer {
        print("TPC numPCs:", TracePC.numPCs())
                                                    // the size of the array is 2^(nbr of bits used by Feature)
        return UnsafeMutableBufferPointer.allocateAndInitializeTo(nil, capacity: 1 << 25)
    }
    subscript(idx: Feature) -> (Complexity, CorpusIndex)? {
        get {
            return (self.baseAddress.unsafelyUnwrapped + Int(idx.bits)).pointee
        }
        set {
            (self.baseAddress.unsafelyUnwrapped + Int(idx.bits)).pointee = newValue
        }
    }
}

extension Int {
    func rounded(upToMultipleOf m: Int) -> Int {
        return ((self + m) / m) * m
    }
}

extension UnsafeMutableBufferPointer where Element == UInt8 {
    // Must have a size that is a multiple of 8
    func forEachNonZeroByte(_ f: (UInt8, Int) -> Void) {
        let buffer = UnsafeMutableRawBufferPointer(self).bindMemory(to: UInt64.self)
        for i in 0 ..< buffer.endIndex {
            let eightBytes = buffer[i]
            guard eightBytes != 0 else { continue }
            for j in 0 ..< 8 {
                let j = 7 &- j
                let w = UInt8((eightBytes >> (j &* 8)) & 0xff)
                guard w != 0 else { continue }
                f(w, i &* 8 &+ j)
            }
        }
    }
}
