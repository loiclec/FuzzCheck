
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

/// Program Counter: the index of an instruction in the program binary
typealias PC = UInt


/// A FuzzerSensor for recording code coverage.
/// Please only use the instance defined by `CodeCoverageSensor.shared`
public final class CodeCoverageSensor: FuzzerSensor {
    static let shared: CodeCoverageSensor = .init()
    /// The maximum number of instrumented code edges allowed by CodeCoverageSensor.
    static let maxNumGuards: Int = 1 << 21
    
    /// The number of instrumented code edges.
    var numGuards: Int = 0

    /// True iff `self` is currently recording the execution of the program
    public var isRecording = false
    
    /// The value at index `i` of this buffer holds the number of time that
    /// the code identified by the `pc_guard` of value `i` was visited.
    var eightBitCounters: UnsafeMutableBufferPointer<UInt16> = .allocateAndInitializeTo(0, capacity: 1)
        
    /// An array holding the `Feature`s describing indirect function calls.
    private var indirectFeatures: [Feature.Indirect] = []
    
    /// An array holding the `Feature`s describing comparisons.
    private var cmpFeatures: [Feature.Comparison] = []
    
    /// Handle a call to the sanitizer code coverage function `trace_pc_guard_init`
    /// It assigns a unique value to every pointer inside [start, stop). These values
    /// are the identifiers of the instrumented code edges.
    /// Reset and resize `edges` and `eightBitCounters`
    func handlePCGuardInit(start: UnsafeMutablePointer<UInt32>, stop: UnsafeMutablePointer<UInt32>) {
        guard start != stop && start.pointee == 0 else { return }
        
        let buffer = UnsafeMutableBufferPointer(start: start, count: stop - start)
        for i in buffer.indices {
            numGuards += 1
            precondition(numGuards < CodeCoverageSensor.maxNumGuards)
            buffer[i] = UInt32(numGuards)
        }
        // Not ideal, but oh well
        eightBitCounters.deallocate()
        eightBitCounters = .allocateAndInitializeTo(0, capacity: numGuards+1)
    }

    /// Handle a call to the sanitizer code coverage function `trace_pc_indir`
    func handlePCIndir(caller: NormalizedPC, callee: NormalizedPC) {
        let (caller, callee) = (caller.value, callee.value)
        let f = Feature.Indirect(caller: caller, callee: callee)
        // TODO: could this be guarded by a lock, or would it ruin performance?
        indirectFeatures.append(f)
    }
    
    /// Call the given function for every unique collected `Feature`.
    /// The features are passed in a deterministic order. Therefore, even if
    /// two different executions of the program trigger the same features but
    /// in a different order, `collectFeatures` will pass them in the same order.
    public func iterateOverCollectedFeatures(_ handle: (Feature) -> Void) {
        
        for i in eightBitCounters.indices where eightBitCounters[i] != 0 {
            let f = Feature.Edge(pcguard: UInt(i), counter: eightBitCounters[i])
            handle(.edge(f))
        }
        
        indirectFeatures.sort()
        cmpFeatures.sort()

        // Ensure we don't call `handle` with the same argument twice.
        // This works because the arrays are sorted.
        var last1: Feature.Indirect? = nil
        for f in indirectFeatures where last1 != f {
            handle(.indirect(f))
            last1 = f
        }
        var last2: Feature.Comparison? = nil
        for f in cmpFeatures where last2 != f {
            handle(.comparison(f))
            last2 = f
        }
    }
    
    func handleTraceCmp <T: BinaryInteger & UnsignedInteger> (pc: NormalizedPC, arg1: T, arg2: T) {
        let f = Feature.Comparison(pc: pc.value, arg1: numericCast(arg1), arg2: numericCast(arg2))
        // TODO: could this be guarded by a lock, or would it ruin performance?
        cmpFeatures.append(f)
    }
    
    public func resetCollectedFeatures() {
        eightBitCounters.assign(repeating: 0)
        indirectFeatures.removeAll(keepingCapacity: true)
        cmpFeatures.removeAll(keepingCapacity: true)
    }
}
