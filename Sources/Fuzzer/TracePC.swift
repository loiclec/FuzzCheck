
import CBuiltinsNotAvailableInSwift
import Darwin

extension UnsafeMutableBufferPointer {
    static func allocateAndInitializeTo(_ x: Element, capacity: Int) -> UnsafeMutableBufferPointer {
        let b = UnsafeMutableBufferPointer.allocate(capacity: capacity)
        b.initialize(repeating: x)
        return b
    }
}

var PCsSet: [PC: Int] = Dictionary(minimumCapacity: TPC.numPCs())
var eightBitCounters = UnsafeMutableBufferPointer<UInt8>.allocateAndInitializeTo(0, capacity: TPC.numPCs())

func counterToFeature <T: BinaryInteger> (_ counter: T) -> UInt32 {
    precondition(counter > 0)
   
    if counter >= 128 { return 7 }
    if counter >= 32  { return 6 }
    if counter >= 16  { return 5 }
    if counter >= 8   { return 4 }
    if counter >= 4   { return 3 }
    if counter >= 3   { return 2 }
    if counter >= 2   { return 1 }
    return 0
}

typealias PC = UInt

final class TracePC {
    // How many bits of PC are used from __sanitizer_cov_trace_pc
    static let maxNumPCs: Int = 1 << 21
    static let tracePCBits: Int = 18
    
    var numGuards: Int = 0
    var modules: [UnsafeMutableBufferPointer<UInt32>] = []
    
    var valueProfileMap: ValueBitMap = .init()
    
    var useCounters: Bool = true
    var useValueProfile: Bool = true
    
    init() {}
    
    func numPCs() -> Int {
        precondition(numGuards > 0 && numGuards < TracePC.maxNumPCs)
        return numGuards+1
    }
    
    func handleInit(start: UnsafeMutablePointer<UInt32>, stop: UnsafeMutablePointer<UInt32>) {
        guard start != stop && start.pointee == 0 else { return }
    
        let buffer = UnsafeMutableBufferPointer(start: start, count: stop - start)
        for i in buffer.indices {
            numGuards += 1
            precondition(numGuards < TracePC.maxNumPCs)
            buffer[i] = UInt32(numGuards)
        }
        modules.append(buffer)
    }

    func handleCallerCallee(caller: Int, callee: Int) {
        let (caller, callee) = (UInt(caller), UInt(callee))
        let bits: UInt = 12
        let mask = (1 << bits) - 1
        let idx: UInt = (caller & mask) | ((callee & mask) << bits)
        _ = valueProfileMap.addValueModPrime(idx)
    }
    
    func getTotalPCCoverage() -> Int {
        return PCsSet.count
    }
    
    func collectFeatures(_ handle: (Feature) -> Void) {
        // a feature is Comparable, and they are passed here in a deterministic, growing order. ref: #mxrvFXBpY9ij
        let N = numPCs()
        
        var feature = Feature(key: 0, coverage: .pc)
        
        for i in 0 ..< N where eightBitCounters[i] != 0 { // TODO: iterate 64bits at a time
            let counterFeatureOffset = counterToFeature(eightBitCounters[i])
            let f = feature &+ (UInt32(i) &* 8 &+ counterFeatureOffset)
            precondition(f.coverage == .pc)
            handle(f)
        }
        
        feature.coverage = .valueProfile
        feature.key = 0
        
        if useValueProfile {
            valueProfileMap.forEach {
                let f = feature &+ $0
                precondition(f.coverage == .valueProfile)
                handle(f)
            }
        }
    }
    
    func handleCmp <T: BinaryInteger> (pc: Int, arg1: T, arg2: T) {
        let pc = PC(pc)
        let argxor = arg1 ^ arg2
        let argdist = UInt(__popcountll(UInt64(argxor)) + 1)

        let idx = ((pc & 4095) + 1) &* argdist
        _ = valueProfileMap.addValue(idx)
    }
    
    func resetMaps() {
        valueProfileMap.reset()
        modules.removeAll()
        UnsafeMutableBufferPointer(rebasing: eightBitCounters[..<numPCs()]).assign(repeating: 0)
    }
}

struct ValueBitMap {
    static let mapSizeInBits: UInt = 1 << 16
    static let mapPrimeMod: UInt = 65371 // Largest Prime < kMapSizeInBits
    static let bitsInWord = UInt(MemoryLayout<UInt>.size * 8)
    static let mapSizeInWords: UInt = ValueBitMap.mapSizeInBits / ValueBitMap.bitsInWord
    
    var map: [UInt] = Array(repeating: 0, count: Int(ValueBitMap.mapSizeInWords))
    
    mutating func reset() {
        for i in map.indices { map[i] = 0 }
    }
    
    // Computes a hash function of Value and sets the corresponding bit.
    // Returns true if the bit was changed from 0 to 1.
    mutating func addValue(_ value: UInt) -> Bool {
        let idx = value % ValueBitMap.mapSizeInBits
        let wordIdx = idx / ValueBitMap.bitsInWord
        let bitIdx = idx % ValueBitMap.bitsInWord
        let old = map[Int(wordIdx)]
        let new = old | (1 << bitIdx)
        map[Int(wordIdx)] = new
        return new != old
    }
    
    mutating func addValueModPrime(_ value: UInt) -> Bool {
        return addValue(value % ValueBitMap.mapPrimeMod)
    }
    
    subscript(idx: UInt) -> Bool {
        precondition(idx < ValueBitMap.mapSizeInBits)
        let wordIdx = idx / ValueBitMap.bitsInWord
        let bitIdx = idx % ValueBitMap.bitsInWord
        return (map[Int(wordIdx)] & (1 << bitIdx)) != 0
    }
    
    var sizeInBits: UInt { return ValueBitMap.mapSizeInBits }
    
    func forEach(_ f: (UInt32) -> Void) {
        for i in 0 ..< ValueBitMap.mapSizeInWords {
            let i = Int(i)
            let M = map[i]
            guard M != 0 else { continue }
            for j in 0 ..< MemoryLayout<UInt>.size * 8 {
                guard M & (UInt(1) << j) != 0 else { continue }
                f(UInt32(i * MemoryLayout<UInt>.size * 8 + j))
            }
        }
    }
}

let TPC: TracePC = TracePC.init()







