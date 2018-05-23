
import Darwin
import CBuiltinsNotAvailableInSwift

@_cdecl("__sanitizer_cov_trace_pc_guard") func trace_pc_guard(g: UnsafePointer<uintptr_t>) {
    let pc = PC(bitPattern: __return_address())
    let idx = Int(g.pointee)
    PCs[idx] = pc
    eightBitCounters[idx] += 1
}

@_cdecl("__sanitizer_cov_trace_pc") func trace_pc() {
    let pc = PC(bitPattern: __return_address())
    let idx = Int(pc & ((1 << TracePC.tracePCBits) - 1))
    PCs[idx] = pc
    eightBitCounters[idx] += 1
}

@_cdecl("__sanitizer_cov_trace_pc_guard_init") func trace_pc_guard_init(start: UnsafeMutablePointer<UInt32>, stop: UnsafeMutablePointer<UInt32>) {
    TPC.handleInit(start: start, stop: stop)
}

@_cdecl("__sanitizer_cov_8bit_counters_init") func eight_bit_counters_init(start: UnsafeMutablePointer<UInt8>, stop: UnsafeMutablePointer<UInt8>) {
    TPC.handleInline8BitCountersInit(start: start, stop: stop)
}

@_cdecl("__sanitizer_cov_pcs_init") func trace_pcs_init(start: UnsafeMutablePointer<uintptr_t>, stop: UnsafeMutablePointer<uintptr_t>) {
    let start = UnsafeMutableRawPointer(start).bindMemory(to: PCTableEntry.self, capacity: 1)
    let stop = UnsafeMutableRawPointer(stop).bindMemory(to: PCTableEntry.self, capacity: 1)
    TPC.handlePCsInit(start: start, stop: stop)
}

@_cdecl("__sanitizer_cov_trace_pc_indir") func trace_pc_indir(callee: PC) {
    let caller = PC(bitPattern: __return_address())
    TPC.handleCallerCallee(caller: caller, callee: callee)
}

@_cdecl("__sanitizer_cov_trace_cmp8") func trace_cmp8(arg1: UInt64, arg2: UInt64) {
    let pc = PC(bitPattern: __return_address())
    TPC.handleCmp(pc: pc, arg1: arg1, arg2: arg2)
}

// Now the __sanitizer_cov_trace_const_cmp[1248] callbacks just mimic
// the behaviour of __sanitizer_cov_trace_cmp[1248] ones. This, however,
// should be changed later to make full use of instrumentation.
@_cdecl("__sanitizer_cov_trace_const_cmp8") func trace_const_cmp8(arg1: UInt64, arg2: UInt64) {
    let pc = PC(bitPattern: __return_address())
    TPC.handleCmp(pc: pc, arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_cmp4") func trace_cmp4(arg1: UInt32, arg2: UInt32) {
    let pc = PC(bitPattern: __return_address())
    TPC.handleCmp(pc: pc, arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_const_cmp4") func trace_const_cmp4(arg1: UInt32, arg2: UInt32) {
    let pc = PC(bitPattern: __return_address())
    TPC.handleCmp(pc: pc, arg1: arg1, arg2: arg2)
}


@_cdecl("__sanitizer_cov_trace_cmp2") func trace_cmp2(arg1: UInt16, arg2: UInt16) {
    let pc = PC(bitPattern: __return_address())
    TPC.handleCmp(pc: pc, arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_const_cmp2") func trace_const_cmp2(arg1: UInt16, arg2: UInt16) {
    let pc = PC(bitPattern: __return_address())
    TPC.handleCmp(pc: pc, arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_cmp1") func trace_cmp1(arg1: UInt8, arg2: UInt8) {
    let pc = PC(bitPattern: __return_address())
    TPC.handleCmp(pc: pc, arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_const_cmp1") func trace_const_cmp1(arg1: UInt8, arg2: UInt8) {
    let pc = PC(bitPattern: __return_address())
    TPC.handleCmp(pc: pc, arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_switch") func trace_switch(val: UInt64, cases: UnsafePointer<UInt64>) {
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
        TPC.handleCmp(pc: pc + PC(i), arg1: UInt16(token), arg2: 0)
    } else if valSizeInBits == 32 {
        TPC.handleCmp(pc: pc + PC(i), arg1: UInt16(token), arg2: 0)
    } else {
        TPC.handleCmp(pc: pc + PC(i), arg1: token, arg2: 0)
    }
}

@_cdecl("__sanitizer_cov_trace_div4") func trace_div4(val: UInt32) {
    let pc = PC(bitPattern: __return_address())
    TPC.handleCmp(pc: pc, arg1: val, arg2: 0)
}

@_cdecl("__sanitizer_cov_trace_div8") func trace_div8(val: UInt64) {
    let pc = PC(bitPattern: __return_address())
    TPC.handleCmp(pc: pc, arg1: val, arg2: 0)
}

@_cdecl("__sanitizer_cov_trace_gep") func trace_gep(idx: uintptr_t) {
    let pc = PC(bitPattern: __return_address())
    TPC.handleCmp(pc: pc, arg1: idx, arg2: 0)
}
// void __sanitizer_weak_hook_memcmp(void *caller_pc, const void *s1, const void *s2, size_t n, int result)
// void __sanitizer_weak_hook_strncmp(void *caller_pc, const char *s1, const char *s2, size_t n, int result)
// etc.

