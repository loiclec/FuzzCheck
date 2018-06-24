
import Darwin
import Foundation
import CBuiltinsNotAvailableInSwift

struct NormalizedPC {
    static var constant: PC = 0
    let raw: PC
    let value: PC
    init(_ raw: PC) {
        self.raw = raw
        self.value = NormalizedPC.constant &- raw 
    }
}

@_cdecl("__sanitizer_cov_trace_pc_guard")
@inline(__always)
func trace_pc_guard(g: UnsafeMutablePointer<UInt32>?) {
    /*
    guard Foundation.Thread.isMainThread else {
        print("Not the main thread!")
        return
    }
    */
    guard TracePC.recording, let g = g else { return }
    let pc = PC(bitPattern: __return_address())
    /*
    let pcToGuard = PCsToGuard[pc]
    switch pcToGuard {
    case .some(let g2):
        if g2 != g.pointee {
            print("Inconsistent PC guards!")
            print("Current PCGuard: \(g.pointee)")
            print("wants to replace: \(g2)")
            print("Old stack trace:")
            PCsToStack[pc]!.forEach { print($0) }
            print("New stack trace:")
            Foundation.Thread.callStackSymbols.forEach { print($0) }
            print("Guards:", "current:", g.pointee, "old:", g2)
        }
        PCsToGuard[pc] = g.pointee
        PCsToStack[pc] = Foundation.Thread.callStackSymbols
    case .none:
        PCsToGuard[pc] = g.pointee
        PCsToStack[pc] = Foundation.Thread.callStackSymbols
    }
    */
    let idx = Int(g.pointee)
    PCs[idx] = pc
    let (result, overflow) = eightBitCounters[idx].addingReportingOverflow(1)
    if !overflow {
        eightBitCounters[idx] = result
    }
}

@_cdecl("__sanitizer_cov_trace_pc_guard_init")
@inline(__always)
func trace_pc_guard_init(start: UnsafeMutablePointer<UInt32>, stop: UnsafeMutablePointer<UInt32>) {
    TracePC.handleInit(start: start, stop: stop)
    //NormalizedPC.constant = PC(bitPattern: start)
}

@_cdecl("__sanitizer_cov_trace_pc_indir")
@inline(__always)
func trace_pc_indir(callee: PC) {
    guard TracePC.recording else { return }

    let caller = PC(bitPattern: __return_address())
    TracePC.handleCallerCallee(caller: NormalizedPC(caller), callee: NormalizedPC(callee))
}

@_cdecl("__sanitizer_cov_trace_cmp8")
@inline(__always)
func trace_cmp8(arg1: UInt64, arg2: UInt64) {
    guard TracePC.recording else { return }
    let pc = PC(bitPattern: __return_address())
    TracePC.handleCmp(pc: NormalizedPC(pc), arg1: arg1, arg2: arg2)
}

// Now the __sanitizer_cov_trace_const_cmp[1248] callbacks just mimic
// the behaviour of __sanitizer_cov_trace_cmp[1248] ones. This, however,
// should be changed later to make full use of instrumentation.
@_cdecl("__sanitizer_cov_trace_const_cmp8")
@inline(__always)
func trace_const_cmp8(arg1: UInt64, arg2: UInt64) {
    guard TracePC.recording else { return }
    let pc = PC(bitPattern: __return_address())
    let x = NormalizedPC(pc)
    TracePC.handleCmp(pc: x, arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_cmp4")
@inline(__always)
func trace_cmp4(arg1: UInt32, arg2: UInt32) {
    guard TracePC.recording else { return }

    let pc = PC(bitPattern: __return_address())
    TracePC.handleCmp(pc: NormalizedPC(pc), arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_const_cmp4")
@inline(__always)
func trace_const_cmp4(arg1: UInt32, arg2: UInt32) {
    guard TracePC.recording else { return }

    let pc = PC(bitPattern: __return_address())
    TracePC.handleCmp(pc: NormalizedPC(pc), arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_cmp2")
@inline(__always)
func trace_cmp2(arg1: UInt16, arg2: UInt16) {
    guard TracePC.recording else { return }

    let pc = PC(bitPattern: __return_address())
    TracePC.handleCmp(pc: NormalizedPC(pc), arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_const_cmp2")
@inline(__always)
func trace_const_cmp2(arg1: UInt16, arg2: UInt16) {
    guard TracePC.recording else { return }

    let pc = PC(bitPattern: __return_address())
    TracePC.handleCmp(pc: NormalizedPC(pc), arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_cmp1")
@inline(__always)
func trace_cmp1(arg1: UInt8, arg2: UInt8) {
    guard TracePC.recording else { return }

    let pc = PC(bitPattern: __return_address())
    TracePC.handleCmp(pc: NormalizedPC(pc), arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_const_cmp1")
@inline(__always)
func trace_const_cmp1(arg1: UInt8, arg2: UInt8) {
    guard TracePC.recording else { return }
    let pc = PC(bitPattern: __return_address())
    TracePC.handleCmp(pc: NormalizedPC(pc), arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_switch")
@inline(__always)
func trace_switch(val: UInt64, cases: UnsafePointer<UInt64>) {
    guard TracePC.recording else { return }

    let n = cases[0]
    let valSizeInBits = cases[1]
    let vals = cases.advanced(by: 2)
    // Skip the most common and the most boring case.
    guard !(vals[Int(n - 1)] < 256 && val < 256) else { return }

    let pc = PC(bitPattern: __return_address())

    var i: Int = 0
    var token: UInt64 = 0
    while i < n {
        defer { i += 1 }
        token = val ^ vals[i]
        guard val >= vals[i] else { break }
    }

    TracePC.handleCmp(pc: NormalizedPC(pc + UInt(i)), arg1: token, arg2: 0)
}

@_cdecl("__sanitizer_cov_trace_div4")
@inline(__always)
func trace_div4(val: UInt32) {
    guard TracePC.recording else { return }

    let pc = PC(bitPattern: __return_address())
    TracePC.handleCmp(pc: NormalizedPC(pc), arg1: val, arg2: 0)
}

@_cdecl("__sanitizer_cov_trace_div8")
@inline(__always)
func trace_div8(val: UInt64) {
    guard TracePC.recording else { return }

    let pc = PC(bitPattern: __return_address())
    TracePC.handleCmp(pc: NormalizedPC(pc), arg1: val, arg2: 0)
}

@_cdecl("__sanitizer_cov_trace_gep")
@inline(__always)
func trace_gep(idx: UInt) {
    fatalError("trace gep")
    //guard TracePC.recording else { return }
    
    //let pc = PC(bitPattern: __return_address())
    //TracePC.handleCmp(pc: NormalizedPC(pc), arg1: idx, arg2: 0)
    //TracePC.handleGep(pc: NormalizedPC(pc), idx: idx)
}
