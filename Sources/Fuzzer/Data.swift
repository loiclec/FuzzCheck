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


struct Feature: Equatable {
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
    
    enum Coverage: UInt8 {
        case pc = 0
        case valueProfile = 1
    }
}

extension Feature {
    static func &+ (lhs: Feature, rhs: UInt32) -> Feature {
        return Feature(bits: lhs.bits &+ rhs)
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
        print("TPC numPCs:", TPC.numPCs())
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

import os

extension UnsafeMutableBufferPointer where Element == UInt8 {
    // Must have a size that is a multiple of 8
    func forEachNonZeroByte(_ f: (UInt8, Int) -> Void) {
        //os_log("for each non-zero byte. size: %d", log: log, type: .debug, self.count)
        let buffer = UnsafeMutableRawBufferPointer(self).bindMemory(to: UInt64.self)
        //os_log("raw buffer of size %d", log: log, type: .debug, raw.count)
        // let buffer = raw
        //os_log("rebound! for i in 0 ..< %d", log: log, type: .debug, buffer.endIndex)
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

struct EightBitCounters {
    let buffer: UnsafeMutableBufferPointer<UInt8> = UnsafeMutableBufferPointer.allocate(capacity: TPC.numPCs() / 8)
}


