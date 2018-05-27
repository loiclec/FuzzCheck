
import CBuiltinsNotAvailableInSwift
import Darwin

typealias Feature = Int

extension UnsafeMutableBufferPointer {
    static func allocateAndInitializeTo(_ x: Element, capacity: Int) -> UnsafeMutableBufferPointer {
        let b = UnsafeMutableBufferPointer.allocate(capacity: capacity)
        b.initialize(repeating: x)
        return b
    }
}

var PCs = UnsafeMutableBufferPointer<PC>.allocateAndInitializeTo(0, capacity: TracePC.maxNumPCs)
var eightBitCounters = UnsafeMutableBufferPointer<UInt8>.allocateAndInitializeTo(0, capacity: TracePC.maxNumPCs)

func counterToFeature <T: BinaryInteger> (_ counter: T) -> CUnsignedInt {
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
        if numGuards == 0 {
            return 1 << TracePC.tracePCBits
        } else {
            return min(TracePC.maxNumPCs, numGuards+1)
        }
    }
    
    func handleInit(start: UnsafeMutablePointer<UInt32>, stop: UnsafeMutablePointer<UInt32>) {
        guard start != stop && start.pointee == 0 else { return }
    
        let buffer = UnsafeMutableBufferPointer(start: start, count: stop - start)
        for i in buffer.indices {
            numGuards += 1
            if numGuards == TracePC.maxNumPCs {
                print("""
                WARNING: The binary has too many instrumented PCs.
                         You may want to reduce the size of the binary
                         for more efficient fuzzing and precise coverage data
                """)
            }
            buffer[i] = UInt32(numGuards % TracePC.maxNumPCs)
        }
        modules.append(buffer)
    }

    func handleCallerCallee(caller: UInt, callee: UInt) {
        let bits: UInt = 12
        let mask = (1 << bits) - 1
        let idx: UInt = (caller & mask) | ((callee & mask) << bits)
        _ = valueProfileMap.addValueModPrime(idx)
    }
    
    func getTotalPCCoverage() -> Int {
        return (1 ..< numPCs()).reduce(0) { $0 + ((PCs[$1] != 0) ? 1 : 0) }
    }
    
    func collectFeatures(_ handleFeature: (Feature) -> Void) {
        let Counters = eightBitCounters
        let N = numPCs()
        
        func handle8BitCounter(_ handleFeature: (Feature) -> Void, _ firstFeature: Feature, _ idx: Int, _ counter: UInt8) -> Void {
            handleFeature(firstFeature + idx * 8 + Int(counterToFeature(counter)))
        }
        
        var firstFeature: Feature = 0
        
        for i in 0 ..< N where Counters[i] != 0 {
            handle8BitCounter(handleFeature, firstFeature, i, Counters[i])
        }
        firstFeature += N * 8
    
        if useValueProfile {
            valueProfileMap.forEach {
                handleFeature(firstFeature + $0)
            }
            firstFeature += Feature(type(of: valueProfileMap).mapSizeInBits)
        }
    }
    
    func handleCmp <T: BinaryInteger> (pc: PC, arg1: T, arg2: T) {
        let argxor = arg1 ^ arg2
        let argdist = UInt(__popcountll(UInt64(argxor)) + 1)

        let idx = ((pc & 4095) + 1) &* argdist
        _ = valueProfileMap.addValue(idx)
    }
    
    func resetMaps() {
        valueProfileMap.reset()
        modules.removeAll()
        eightBitCounters.assign(repeating: 0)
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
    
    func forEach(_ f: (Int) -> Void) {
        for i in 0 ..< ValueBitMap.mapSizeInWords {
            let M = map[Int(i)]
            guard M != 0 else { continue }
            for j in 0 ..< MemoryLayout<UInt>.size * 8 {
                guard M & (UInt(1) << j) != 0 else { continue }
                f(Int(i) * MemoryLayout<UInt>.size * 8 + j)
            }
        }
    }
}

let TPC: TracePC = TracePC.init()







