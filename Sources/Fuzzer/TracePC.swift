
import CBuiltinsNotAvailableInSwift
import Darwin
import Foundation

extension UnsafeMutableBufferPointer {
    static func allocateAndInitializeTo(_ x: Element, capacity: Int) -> UnsafeMutableBufferPointer {
        let b = UnsafeMutableBufferPointer.allocate(capacity: capacity)
        b.initialize(repeating: x)
        return b
    }
}

var PCs = UnsafeMutableBufferPointer<UInt>.allocateAndInitializeTo(0, capacity: TracePC.numPCs().rounded(upToMultipleOf: 8))
var eightBitCounters = UnsafeMutableBufferPointer<UInt8>.allocateAndInitializeTo(0, capacity: TracePC.numPCs().rounded(upToMultipleOf: 8) )

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

enum TracePC {
    // How many bits of PC are used from __sanitizer_cov_trace_pc
    static let maxNumPCs: Int = 1 << 21
    static var numGuards: Int = 0
    static var crashed = false
    
    private static var indirectFeatures: [Feature.Indirect] = []
    private static var valueProfileFeatures: [Feature.ValueProfile] = []
    
    static func numPCs() -> Int {
        precondition(numGuards > 0 && numGuards < TracePC.maxNumPCs)
        return numGuards+1
    }

    static func handleInit(start: UnsafeMutablePointer<UInt32>, stop: UnsafeMutablePointer<UInt32>) {
        guard start != stop && start.pointee == 0 else { return }
        
        let buffer = UnsafeMutableBufferPointer(start: start, count: stop - start)
        for i in buffer.indices {
            numGuards += 1
            precondition(numGuards < TracePC.maxNumPCs)
            buffer[i] = UInt32(numGuards)
        }
    }

    
    static func handleCallerCallee(caller: NormalizedPC, callee: NormalizedPC) {
        let (caller, callee) = (caller.value, callee.value)
        indirectFeatures.append(.init(caller: caller, callee: callee))
    }
    
    static func getTotalPCCoverage() -> Int {
        return PCs.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
    }
    
    static func collectFeatures(debug: Bool, _ handle: (Feature) -> Void) {
        
        // the features are passed here in a deterministic order. ref: #mxrvFXBpY9ij
        let N = numPCs()
        for i in 0 ..< N where eightBitCounters[i] != 0 {
            let f = Feature.Edge(pcguard: UInt(i), intensity: eightBitCounters[i])
            handle(.edge(f))
        }
        
        indirectFeatures.sort()
        valueProfileFeatures.sort()

        var last: Feature? = nil
        for f in indirectFeatures where last != .indirect(f) {
            handle(.indirect(f))
            last = .indirect(f)
        }
        for f in valueProfileFeatures where last != .valueProfile(f) {
            handle(.valueProfile(f))
            last = .valueProfile(f)
        }
    }
    
    static func handleCmp <T: BinaryInteger & UnsignedInteger> (pc: NormalizedPC, arg1: T, arg2: T) {
        valueProfileFeatures.append(.init(pc: pc.value, arg1: numericCast(arg1), arg2: numericCast(arg2)))
    }
    
    static func resetMaps() {
        UnsafeMutableBufferPointer(rebasing: eightBitCounters[..<numPCs()]).assign(repeating: 0)
        indirectFeatures.removeAll(keepingCapacity: true)
        valueProfileFeatures.removeAll(keepingCapacity: true)
    }
    
    static var recording = false
}
