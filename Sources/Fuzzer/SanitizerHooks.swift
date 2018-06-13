
import Darwin
import CBuiltinsNotAvailableInSwift

struct NormalizedPC {
    static var constant: PC = 0
    let value: PC
    init(_ raw: PC) {
        self.value = raw &- NormalizedPC.constant
    }
}

@_cdecl("__sanitizer_cov_trace_pc_guard") func trace_pc_guard(g: UnsafePointer<UInt32>) {
    guard TracePC.recording else { return }
    let pc = PC(bitPattern: __return_address())
    let idx = Int(g.pointee)
    PCs[idx] = pc
    _ = NormalizedPC(pc)
    eightBitCounters[idx] = eightBitCounters[idx] &+ 1
}

@_cdecl("__sanitizer_cov_trace_pc_guard_init") func trace_pc_guard_init(start: UnsafeMutablePointer<UInt32>, stop: UnsafeMutablePointer<UInt32>) {
    TracePC.handleInit(start: start, stop: stop)
    NormalizedPC.constant = PC(bitPattern: start)
}

@_cdecl("__sanitizer_cov_trace_pc_indir") func trace_pc_indir(callee: PC) {
    guard TracePC.recording else { return }

    let caller = PC(bitPattern: __return_address())
    TracePC.handleCallerCallee(caller: NormalizedPC(caller), callee: NormalizedPC(callee))
}

@_cdecl("__sanitizer_cov_trace_cmp8") func trace_cmp8(arg1: UInt64, arg2: UInt64) {
    guard TracePC.recording else { return }
    let pc = PC(bitPattern: __return_address())
    TracePC.handleCmp(pc: NormalizedPC(pc), arg1: arg1, arg2: arg2)
}

// Now the __sanitizer_cov_trace_const_cmp[1248] callbacks just mimic
// the behaviour of __sanitizer_cov_trace_cmp[1248] ones. This, however,
// should be changed later to make full use of instrumentation.
@_cdecl("__sanitizer_cov_trace_const_cmp8") func trace_const_cmp8(arg1: UInt64, arg2: UInt64) {
    guard TracePC.recording else { return }
    let pc = PC(bitPattern: __return_address())
    let x = NormalizedPC(pc)
    TracePC.handleCmp(pc: x, arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_cmp4") func trace_cmp4(arg1: UInt32, arg2: UInt32) {
    guard TracePC.recording else { return }

    let pc = PC(bitPattern: __return_address())
    TracePC.handleCmp(pc: NormalizedPC(pc), arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_const_cmp4") func trace_const_cmp4(arg1: UInt32, arg2: UInt32) {
    guard TracePC.recording else { return }

    let pc = PC(bitPattern: __return_address())
    TracePC.handleCmp(pc: NormalizedPC(pc), arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_cmp2") func trace_cmp2(arg1: UInt16, arg2: UInt16) {
    guard TracePC.recording else { return }

    let pc = PC(bitPattern: __return_address())
    TracePC.handleCmp(pc: NormalizedPC(pc), arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_const_cmp2") func trace_const_cmp2(arg1: UInt16, arg2: UInt16) {
    guard TracePC.recording else { return }

    let pc = PC(bitPattern: __return_address())
    TracePC.handleCmp(pc: NormalizedPC(pc), arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_cmp1") func trace_cmp1(arg1: UInt8, arg2: UInt8) {
    guard TracePC.recording else { return }

    let pc = PC(bitPattern: __return_address())
    TracePC.handleCmp(pc: NormalizedPC(pc), arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_const_cmp1") func trace_const_cmp1(arg1: UInt8, arg2: UInt8) {
    guard TracePC.recording else { return }
    let pc = PC(bitPattern: __return_address())
    TracePC.handleCmp(pc: NormalizedPC(pc), arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_switch") func trace_switch(val: UInt64, cases: UnsafePointer<UInt64>) {
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

    if valSizeInBits == 16 {
        TracePC.handleCmp(pc: NormalizedPC(pc + UInt(i)), arg1: UInt16(token), arg2: 0)
    } else if valSizeInBits == 32 {
        TracePC.handleCmp(pc: NormalizedPC(pc + UInt(i)), arg1: UInt32(token), arg2: 0)
    } else {
        TracePC.handleCmp(pc: NormalizedPC(pc + UInt(i)), arg1: token, arg2: 0)
    }
}

@_cdecl("__sanitizer_cov_trace_div4") func trace_div4(val: UInt32) {
    guard TracePC.recording else { return }

    let pc = PC(bitPattern: __return_address())
    TracePC.handleCmp(pc: NormalizedPC(pc), arg1: val, arg2: 0)
}

@_cdecl("__sanitizer_cov_trace_div8") func trace_div8(val: UInt64) {
    guard TracePC.recording else { return }

    let pc = PC(bitPattern: __return_address())
    TracePC.handleCmp(pc: NormalizedPC(pc), arg1: val, arg2: 0)
}

@_cdecl("__sanitizer_cov_trace_gep") func trace_gep(idx: UInt) {
    guard TracePC.recording else { return }

    let pc = PC(bitPattern: __return_address())
    TracePC.handleCmp(pc: NormalizedPC(pc), arg1: idx, arg2: 0)
}
