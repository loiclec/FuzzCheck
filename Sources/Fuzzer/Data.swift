//
//  Data.swift
//  Fuzzer
//
//  Created by Loïc Lecrenier on 27/05/2018.
//

public enum Complexity {
    case zero
    case magnitudeOf(Double)
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

    struct Score: CustomStringConvertible {
        var s: Int
        var description: String { return s.description }
    }

    var importance: Score {
        switch self {
        case .pc:
            return .init(s: 1)
        case .valueProfile:
            return .init(s: 1)
//        case .newComparison:
//            return 10
//        case .redundantComparison:
//            return 1
        }
    }
}

typealias FeatureDictionary = UnsafeMutableBufferPointer<(Complexity, CorpusIndex?)>

extension UnsafeMutableBufferPointer where Element == (Complexity, CorpusIndex?) {
    static func createEmpty() -> UnsafeMutableBufferPointer {
        return UnsafeMutableBufferPointer.allocateAndInitializeTo((.zero, nil), capacity: 1 << 21)
    }
    subscript(idx: Feature.Key) -> (Complexity, CorpusIndex?) {
        get {
            return self[idx.k % count]
        }
        set {
            self[idx.k % count] = newValue
        }
    }
}





