//
//  Data.swift
//  Fuzzer
//
//  Created by Loïc Lecrenier on 27/05/2018.
//

public enum Feature: Equatable, Hashable {
    case indirect(Indirect)
    case edge(Edge)
    case valueProfile(Cmp)
    case gep(GEP)
}

extension Feature {
    var score: Double {
        switch self {
        case .indirect(_):
            return 1
        case .edge(_):
            return 1
        case .valueProfile(_):
            return 1
        case .gep(_):
            return 1
        }
    }
}


func scoreFromByte <T: BinaryInteger> (_ counter: T) -> UInt32 {
    if counter >= 128 { return 7 }
    if counter >= 32  { return 6 }
    if counter >= 16  { return 5 }
    if counter >= 8   { return 4 }
    if counter >= 4   { return 3 }
    if counter >= 3   { return 2 }
    if counter >= 2   { return 1 }
    return 0
}


extension Feature {
    public struct Indirect: Equatable, Hashable {
        let caller: UInt
        let callee: UInt
    }
    public struct Edge: Equatable, Hashable {
        let pcguard: UInt
        let intensity: UInt8
        
        init(pcguard: UInt, reducedIntensity: UInt8) {
            self.pcguard = pcguard
            self.intensity = reducedIntensity
        }
        
        init(pcguard: UInt, intensity: UInt8) {
            self.pcguard = pcguard
            self.intensity = UInt8(scoreFromByte(intensity))
        }
    }
    public struct Cmp: Equatable, Hashable {
        let pc: UInt
        let argxordist: UInt64
        //let arg1: UInt64
        //let arg2: UInt64
        init(pc: UInt, argxordist: UInt64) {
            self.pc = pc
            self.argxordist = argxordist
        }
        init(pc: UInt, arg1: UInt64, arg2: UInt64) {
            self.pc = pc
            self.argxordist = UInt64(scoreFromByte((arg1 &- arg2).nonzeroBitCount))
        }
    }
    public struct GEP: Equatable, Hashable {
        let pc: UInt
        let argcount: UInt8
        
        init(pc: UInt, argcount: UInt8) {
            self.pc = pc
            self.argcount = argcount
        }
        init(pc: UInt, arg: UInt64) {
            self.pc = pc
            self.argcount = UInt8(arg.nonzeroBitCount)
        }
    }
}

extension Feature {
    var pcGroup: PC {
        switch self {
        case .indirect(let x):
            return x.callee
        case .edge(let x):
            return x.pcguard << 32
        case .valueProfile(let x):
            return x.pc
        case .gep(let x):
            return x.pc
        }
    }
}


extension Feature.Indirect: Comparable {
    public static func < (lhs: Feature.Indirect, rhs: Feature.Indirect) -> Bool {
        if lhs.caller < rhs.caller {
            return true
        } else if lhs.caller == rhs.caller {
            return lhs.callee < rhs.callee
        } else {
            return false
        }
    }
}

extension Feature.Cmp: Comparable {
    public static func < (lhs: Feature.Cmp, rhs: Feature.Cmp) -> Bool {
        if lhs.pc < rhs.pc {
            return true
        } else if lhs.pc == rhs.pc {
            return lhs.argxordist < rhs.argxordist
        } else {
            return false
        }
    }
}

extension Feature.GEP: Comparable {
    public static func < (lhs: Feature.GEP, rhs: Feature.GEP) -> Bool {
        if lhs.pc < rhs.pc {
            return true
        } else if lhs.pc == rhs.pc {
            return lhs.argcount < rhs.argcount
        } else {
            return false
        }
    }
}

extension Feature: Codable {
    enum Kind: String, Codable {
        case indirect
        case edge
        case valueProfile
        case gep
    }
    
    enum CodingKey: Swift.CodingKey {
        case kind
        case pc
        case pcguard
        case intensity
        case arg1
        case arg2
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
            self = .edge(.init(pcguard: pcguard, reducedIntensity: intensity))
        case .valueProfile:
            let pc = try container.decode(UInt.self, forKey: .pc)
            let argxordist = try container.decode(UInt64.self, forKey: .arg1) // FIXME
            self = .valueProfile(.init(pc: pc, argxordist: argxordist))
        case .gep:
            let pc = try container.decode(UInt.self, forKey: .pc)
            let argcount = try container.decode(UInt8.self, forKey: .arg1) // FIXME
            self = .gep(.init(pc: pc, argcount: argcount))
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
        case .valueProfile(let x):
            try container.encode(Kind.valueProfile, forKey: .kind)
            try container.encode(x.pc, forKey: .pc)
            try container.encode(x.argxordist, forKey: .arg1) // FIXME
        case .gep(let x):
            try container.encode(Kind.gep, forKey: .kind)
            try container.encode(x.pc, forKey: .pc)
            try container.encode(x.argcount, forKey: .arg1) // FIXME
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
