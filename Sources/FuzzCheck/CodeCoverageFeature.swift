//
//  Feature.swift
//  FuzzCheck
//
//  Created by Loïc Lecrenier on 27/05/2018.
//

extension CodeCoverageSensor {
    public enum Feature: FuzzerSensorFeature, Equatable, Hashable {
        case indirect(Indirect)
        case edge(Edge)
        case comparison(Comparison)
    }
}

extension CodeCoverageSensor.Feature {
    public var score: Double {
        switch self {
        case .indirect(_):
            return 1
        case .edge(_):
            return 1
        case .comparison(_):
            return 1
        }
    }
}


func scoreFromCounter <T: BinaryInteger & FixedWidthInteger & UnsignedInteger> (_ counter: T) -> UInt8 {
    guard counter != T.max else { return UInt8(T.bitWidth) }
    if counter <= 3 {
        return UInt8(counter)
    } else {
        return UInt8(T.bitWidth - counter.leadingZeroBitCount) + 1
    }
}


extension CodeCoverageSensor.Feature {
    public struct Indirect: Equatable, Hashable {
        let caller: UInt
        let callee: UInt
    }
    public struct Edge: Equatable, Hashable {
        let pcguard: UInt
        let intensity: UInt8
        
        init(pcguard: UInt, intensity: UInt8) {
            self.pcguard = pcguard
            self.intensity = intensity
        }
        init(pcguard: UInt, counter: UInt16) {
            self.init(pcguard: pcguard, intensity: scoreFromCounter(counter))
        }
    }
    
    public struct Comparison: Equatable, Hashable {
        let pc: UInt
        let argxordist: UInt8
        
        init(pc: UInt, argxordist: UInt8) {
            self.pc = pc
            self.argxordist = argxordist
        }
        init(pc: UInt, arg1: UInt64, arg2: UInt64) {
            self.init(pc: pc, argxordist: scoreFromCounter(UInt8((arg1 &- arg2).nonzeroBitCount)))
        }
    }
}

extension CodeCoverageSensor.Feature.Indirect: Comparable {
    public static func < (lhs: CodeCoverageSensor.Feature.Indirect, rhs: CodeCoverageSensor.Feature.Indirect) -> Bool {
        return (lhs.caller, lhs.callee) < (rhs.caller, rhs.callee)
    }
}

extension CodeCoverageSensor.Feature.Comparison: Comparable {
    public static func < (lhs: CodeCoverageSensor.Feature.Comparison, rhs: CodeCoverageSensor.Feature.Comparison) -> Bool {
        return (lhs.pc, lhs.argxordist) < (rhs.pc, rhs.argxordist)
    }
}

extension CodeCoverageSensor.Feature: Codable {
    enum Kind: String, Codable {
        case indirect
        case edge
        case comparison
    }
    
    enum CodingKey: Swift.CodingKey {
        case kind
        case pc
        case pcguard
        case intensity
        case argxordist
        case caller
        case callee
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKey.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .indirect:
            let caller = try container.decode(UInt.self, forKey: .caller)
            let callee = try container.decode(UInt.self, forKey: .callee)
            self = .indirect(.init(caller: caller, callee: callee))
        case .edge:
            let pcguard = try container.decode(UInt.self, forKey: .pcguard)
            let intensity = try container.decode(UInt8.self, forKey: .intensity)
            self = .edge(.init(pcguard: pcguard, intensity: intensity))
        case .comparison:
            let pc = try container.decode(UInt.self, forKey: .pc)
            let argxordist = try container.decode(UInt8.self, forKey: .argxordist)
            self = .comparison(.init(pc: pc, argxordist: argxordist))
        }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKey.self)
        switch self {
        case .indirect(let x):
            try container.encode(Kind.indirect, forKey: .kind)
            try container.encode(x.caller, forKey: .caller)
            try container.encode(x.callee, forKey: .callee)
        case .edge(let x):
            try container.encode(Kind.edge, forKey: .kind)
            try container.encode(x.pcguard, forKey: .pcguard)
            try container.encode(x.intensity, forKey: .intensity)
        case .comparison(let x):
            try container.encode(Kind.comparison, forKey: .kind)
            try container.encode(x.pc, forKey: .pc)
            try container.encode(x.argxordist, forKey: .argxordist)
        }
    }
}
