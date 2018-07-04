
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

/// Program Counter: the index of an instruction in the binary
typealias PC = UInt

/// Trace-Program-Counters: a namespace holding the data and functions
/// to record code coverage. The code coverage consists of `Feature`s.
/// For example, a feature might be the identifier of a code block/edge,
/// or the result of a comparison operation for a certain program counter.
enum TracePC {

    /// The maximum number of instrumented code edges allowed by TracePC.
    static let maxNumGuards: Int = 1 << 21
    
    /// The number of instrumented code edges.
    static var numGuards: Int = 0

    /// True if the program crashed
    static var crashed = false
    
    /// A bit array. The bit at index `i` of this buffer is true iff the
    /// code edge identified by the `pc_guard` of value `i` was visited.
    /// Unlike `eightBitCounters`, this property is never reset during the
    /// lifetime of the program. Therefore, it represents the total
    /// cumulative edge coverage reached since the initial launch.
    static var edges: UnsafeMutableBufferPointer<UInt> = {
        //  How do we know that `numGuards` has the correct value?
        //  - PCs should never be used before all the `handlePCGuardInit`
        //    calls are finished
        //  - This condition is respected: no `trace_pc_guard_init` function
        //    will be called after any `trace_pc_guard` function call
        precondition(numGuards > 0)
        return .allocateAndInitializeTo(0, capacity: numGuards+1)
    }()
    
    /// The value at index `i` of this buffer holds the number of time that
    /// the code identified by the `pc_guard` of value `i` was visited.
    static var eightBitCounters: UnsafeMutableBufferPointer<UInt16> = {
        precondition(numGuards > 0)
        //  How do we know that `numGuards` has the correct value?
        //  - eightBitCounters should never be used before all the
        //    `handlePCGuardInit` calls are finished
        //  - This condition is respected: no `trace_pc_guard_init` function
        //    will be called after any `trace_pc_guard` function call
        return .allocateAndInitializeTo(0, capacity: numGuards+1)
    }()
    
    /// Return the total number of edges that were visited
    static func getTotalEdgeCoverage() -> Int {
        return edges.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
    }
    
    /// An array holding the `Feature`s describing indirect function calls.
    private static var indirectFeatures: [(Feature.Indirect, Feature.Indirect.Reduced)] = []
    
    /// An array holding the `Feature`s describing comparisons.
    private static var cmpFeatures: [(Feature.Comparison, Feature.Comparison.Reduced)] = []
    
    /// Handle a call to the sanitizer code coverage function `trace_pc_guard_init`
    /// It assigns a unique value to every pointer inside [start, stop). These values
    /// are the identifiers of the instrumented code edges.
    /// Update `TracePC.numGuards` appropriately.
    static func handlePCGuardInit(start: UnsafeMutablePointer<UInt32>, stop: UnsafeMutablePointer<UInt32>) {
        guard start != stop && start.pointee == 0 else { return }
        
        let buffer = UnsafeMutableBufferPointer(start: start, count: stop - start)
        for i in buffer.indices {
            numGuards += 1
            precondition(numGuards < TracePC.maxNumGuards)
            buffer[i] = UInt32(numGuards)
        }
    }

    /// Handle a call to the sanitizer code coverage function `trace_pc_indir`
    static func handlePCIndir(caller: NormalizedPC, callee: NormalizedPC) {
        let (caller, callee) = (caller.value, callee.value)
        let f = Feature.Indirect(caller: caller, callee: callee)
        indirectFeatures.append((f, f.reduced))
    }
    
    /// Call the given function for every unique collected `Feature`.
    /// The features are passed in a deterministic order. Therefore, even if
    /// two different executions of the program trigger the same features but
    /// in a different order, `collectFeatures` will pass them in the same order.
    static func collectFeatures(_ handle: (Feature) -> Void) {
        
        for i in eightBitCounters.indices where eightBitCounters[i] != 0 {
            let f = Feature.Edge(pcguard: UInt(i), counter: eightBitCounters[i])
            handle(.edge(f))
        }
        
        indirectFeatures.sort { ($0.1 < $1.1) }
        cmpFeatures.sort { ($0.1 < $1.1) }

        // Ensure we don't call `handle` with the same argument twice.
        // This works because the arrays are sorted.
        var last1: Feature.Indirect.Reduced? = nil
        for (f, rf) in indirectFeatures where last1 != rf {
            handle(.indirect(f))
            last1 = rf
        }
        var last2: Feature.Comparison.Reduced? = nil
        for (f, rf) in cmpFeatures where last2 != rf {
            handle(.comparison(f))
            last2 = rf
        }
    }
    
    static func handleTraceCmp <T: BinaryInteger & UnsignedInteger> (pc: NormalizedPC, arg1: T, arg2: T) {
        let f = Feature.Comparison(pc: pc.value, arg1: numericCast(arg1), arg2: numericCast(arg2))
        cmpFeatures.append((f, f.reduced))
    }
    
    static func resetTestRecordings() {
        eightBitCounters.assign(repeating: 0)
        indirectFeatures.removeAll(keepingCapacity: true)
        cmpFeatures.removeAll(keepingCapacity: true)
    }
    
    static var recording = false
}
