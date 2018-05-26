
import Darwin
import CBuiltinsNotAvailableInSwift

@_cdecl("__sanitizer_cov_trace_pc_guard") func trace_pc_guard(g: UnsafePointer<UInt32>) {
    //print("trace_pc_guard pc")
    let pc = PC(bitPattern: __return_address())
    let idx = Int(g.pointee)
    PCs[idx] = pc
    eightBitCounters[idx] = eightBitCounters[idx] &+ 1
    //print(idx, pc)
}

@_cdecl("__sanitizer_cov_trace_pc") func trace_pc() {
    // // print("trace_pc pc")
    // let pc = PC(bitPattern: __return_address())
    // let idx = Int(pc & ((1 << TracePC.tracePCBits) - 1))
    // PCs[idx] = pc
    // eightBitCounters[idx] = eightBitCounters[idx] &+ 1
}

@_cdecl("__sanitizer_cov_trace_pc_guard_init") func trace_pc_guard_init(start: UnsafeMutablePointer<UInt32>, stop: UnsafeMutablePointer<UInt32>) {
    // print("trace_pc_guard_init")
    TPC.handleInit(start: start, stop: stop)
}

@_cdecl("__sanitizer_cov_8bit_counters_init") func eight_bit_counters_init(start: UnsafeMutablePointer<UInt8>, stop: UnsafeMutablePointer<UInt8>) {
    print("8bit_counters_init")
    TPC.handleInline8BitCountersInit(start: start, stop: stop)
}

@_cdecl("__sanitizer_cov_pcs_init") func pcs_init(start: UnsafeMutablePointer<UInt>, stop: UnsafeMutablePointer<UInt>) {
    // print("pcs_init start")
    // let start = UnsafeMutableRawPointer(start).bindMemory(to: PCTableEntry.self, capacity: 1)
    // let stop = UnsafeMutableRawPointer(stop).bindMemory(to: PCTableEntry.self, capacity: 1)
    // TPC.handlePCsInit(start: start, stop: stop)
}

@_cdecl("__sanitizer_cov_trace_pc_indir") func trace_pc_indir(callee: PC) {
    // print("pc_indir callee")
  //  let caller = PC(bitPattern: __return_address())
//    TPC.handleCallerCallee(caller: caller, callee: callee)
}

@_cdecl("__sanitizer_cov_trace_cmp8") func trace_cmp8(arg1: UInt64, arg2: UInt64) {
    // print("trace_cmp8 \(arg1) \(arg2)")
    // let pc = PC(bitPattern: __return_address())
    // TPC.handleCmp(pc: pc, arg1: arg1, arg2: arg2)
}

// Now the __sanitizer_cov_trace_const_cmp[1248] callbacks just mimic
// the behaviour of __sanitizer_cov_trace_cmp[1248] ones. This, however,
// should be changed later to make full use of instrumentation.
@_cdecl("__sanitizer_cov_trace_const_cmp8") func trace_const_cmp8(arg1: UInt64, arg2: UInt64) {
    
    // // print("trace_const_cmp8 \(arg1) \(arg2)")
    // let pc = PC(bitPattern: __return_address())
    // // print("will handleCmp")
    // TPC.handleCmp(pc: pc, arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_cmp4") func trace_cmp4(arg1: UInt32, arg2: UInt32) {
    // // print("trace_cmp4 arg1")
    // let pc = PC(bitPattern: __return_address())
    // TPC.handleCmp(pc: pc, arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_const_cmp4") func trace_const_cmp4(arg1: UInt32, arg2: UInt32) {
    // // print("trace_const_cmp4 arg1")
    // let pc = PC(bitPattern: __return_address())
    // TPC.handleCmp(pc: pc, arg1: arg1, arg2: arg2)
}


@_cdecl("__sanitizer_cov_trace_cmp2") func trace_cmp2(arg1: UInt16, arg2: UInt16) {
    // let pc = PC(bitPattern: __return_address())
    // TPC.handleCmp(pc: pc, arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_const_cmp2") func trace_const_cmp2(arg1: UInt16, arg2: UInt16) {
    // let pc = PC(bitPattern: __return_address())
    // TPC.handleCmp(pc: pc, arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_cmp1") func trace_cmp1(arg1: UInt8, arg2: UInt8) {
    // let pc = PC(bitPattern: __return_address())
    // TPC.handleCmp(pc: pc, arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_const_cmp1") func trace_const_cmp1(arg1: UInt8, arg2: UInt8) {
    // let pc = PC(bitPattern: __return_address())
    // TPC.handleCmp(pc: pc, arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_switch") func trace_switch(val: UInt64, cases: UnsafePointer<UInt64>) {
    // let n = cases[0]
    // // print("trace_switch val: \(val) n: \(n) cases: \(cases)")
    // let valSizeInBits = cases[1]
    // let vals = cases.advanced(by: 2)
    // // Skip the most common and the most boring case.
    // guard !(vals[Int(n - 1)] < 256 && val < 256) else { return }

    // let pc = PC(bitPattern: __return_address())
    
    // var i: Int = 0
    // var token: UInt64 = 0
    // while i < n {
    //     defer { i += 1 }
    //     token = val ^ vals[i]
    //     guard val >= vals[i] else { break }
    // }

    // if valSizeInBits == 16 {
    //     TPC.handleCmp(pc: pc + PC(i), arg1: UInt16(token), arg2: 0)
    // } else if valSizeInBits == 32 {
    //     TPC.handleCmp(pc: pc + PC(i), arg1: UInt16(token), arg2: 0)
    // } else {
    //     TPC.handleCmp(pc: pc + PC(i), arg1: token, arg2: 0)
    // }
}

@_cdecl("__sanitizer_cov_trace_div4") func trace_div4(val: UInt32) {
    // let pc = PC(bitPattern: __return_address())
    // TPC.handleCmp(pc: pc, arg1: val, arg2: 0)
}

@_cdecl("__sanitizer_cov_trace_div8") func trace_div8(val: UInt64) {
    // let pc = PC(bitPattern: __return_address())
    // TPC.handleCmp(pc: pc, arg1: val, arg2: 0)
}

@_cdecl("__sanitizer_cov_trace_gep") func trace_gep(idx: UInt) {
    // let pc = PC(bitPattern: __return_address())
    // TPC.handleCmp(pc: pc, arg1: idx, arg2: 0)
}

// void __sanitizer_weak_hook_memcmp(void *caller_pc, const void *s1, const void *s2, Int n, int result)
// void __sanitizer_weak_hook_strncmp(void *caller_pc, const char *s1, const char *s2, Int n, int result)
// etc.

/*
 
extern "C" {
ATTRIBUTE_INTERFACE
ATTRIBUTE_NO_SANITIZE_ALL
void __sanitizer_cov_trace_pc_guard(uint32_t *Guard) {
  UInt PC = reinterpret_cast<UInt>(__builtin_return_address(0));
  uint32_t Idx = *Guard;
  __sancov_trace_pc_pcs[Idx] = PC;
  __sancov_trace_pc_guard_8bit_counters[Idx]++;
}

// Best-effort support for -fsanitize-coverage=trace-pc, which is available
// in both Clang and GCC.
ATTRIBUTE_INTERFACE
ATTRIBUTE_NO_SANITIZE_ALL
void __sanitizer_cov_trace_pc() {
  UInt PC = reinterpret_cast<UInt>(__builtin_return_address(0));
  UInt Idx = PC & (((UInt)1 << fuzzer::TracePC::kTracePcBits) - 1);
  __sancov_trace_pc_pcs[Idx] = PC;
  __sancov_trace_pc_guard_8bit_counters[Idx]++;
}

ATTRIBUTE_INTERFACE
void __sanitizer_cov_trace_pc_guard_init(uint32_t *Start, uint32_t *Stop) {
  fuzzer::TPC.HandleInit(Start, Stop);
}

ATTRIBUTE_INTERFACE
void __sanitizer_cov_8bit_counters_init(uint8_t *Start, uint8_t *Stop) {
  fuzzer::TPC.HandleInline8bitCountersInit(Start, Stop);
}

ATTRIBUTE_INTERFACE
void __sanitizer_cov_pcs_init(const UInt *pcs_beg,
                              const UInt *pcs_end) {
  fuzzer::TPC.HandlePCsInit(pcs_beg, pcs_end);
}

ATTRIBUTE_INTERFACE
ATTRIBUTE_NO_SANITIZE_ALL
void __sanitizer_cov_trace_pc_indir(UInt Callee) {
  UInt PC = reinterpret_cast<UInt>(__builtin_return_address(0));
  fuzzer::TPC.HandleCallerCallee(PC, Callee);
}

ATTRIBUTE_INTERFACE
ATTRIBUTE_NO_SANITIZE_ALL
ATTRIBUTE_TARGET_POPCNT
void __sanitizer_cov_trace_cmp8(uint64_t Arg1, uint64_t Arg2) {
  UInt PC = reinterpret_cast<UInt>(__builtin_return_address(0));
  fuzzer::TPC.HandleCmp(PC, Arg1, Arg2);
}

ATTRIBUTE_INTERFACE
ATTRIBUTE_NO_SANITIZE_ALL
ATTRIBUTE_TARGET_POPCNT
// Now the __sanitizer_cov_trace_const_cmp[1248] callbacks just mimic
// the behaviour of __sanitizer_cov_trace_cmp[1248] ones. This, however,
// should be changed later to make full use of instrumentation.
void __sanitizer_cov_trace_const_cmp8(uint64_t Arg1, uint64_t Arg2) {
  UInt PC = reinterpret_cast<UInt>(__builtin_return_address(0));
  fuzzer::TPC.HandleCmp(PC, Arg1, Arg2);
}

ATTRIBUTE_INTERFACE
ATTRIBUTE_NO_SANITIZE_ALL
ATTRIBUTE_TARGET_POPCNT
void __sanitizer_cov_trace_cmp4(uint32_t Arg1, uint32_t Arg2) {
  UInt PC = reinterpret_cast<UInt>(__builtin_return_address(0));
  fuzzer::TPC.HandleCmp(PC, Arg1, Arg2);
}

ATTRIBUTE_INTERFACE
ATTRIBUTE_NO_SANITIZE_ALL
ATTRIBUTE_TARGET_POPCNT
void __sanitizer_cov_trace_const_cmp4(uint32_t Arg1, uint32_t Arg2) {
  UInt PC = reinterpret_cast<UInt>(__builtin_return_address(0));
  fuzzer::TPC.HandleCmp(PC, Arg1, Arg2);
}

ATTRIBUTE_INTERFACE
ATTRIBUTE_NO_SANITIZE_ALL
ATTRIBUTE_TARGET_POPCNT
void __sanitizer_cov_trace_cmp2(uint16_t Arg1, uint16_t Arg2) {
  UInt PC = reinterpret_cast<UInt>(__builtin_return_address(0));
  fuzzer::TPC.HandleCmp(PC, Arg1, Arg2);
}

ATTRIBUTE_INTERFACE
ATTRIBUTE_NO_SANITIZE_ALL
ATTRIBUTE_TARGET_POPCNT
void __sanitizer_cov_trace_const_cmp2(uint16_t Arg1, uint16_t Arg2) {
  UInt PC = reinterpret_cast<UInt>(__builtin_return_address(0));
  fuzzer::TPC.HandleCmp(PC, Arg1, Arg2);
}

ATTRIBUTE_INTERFACE
ATTRIBUTE_NO_SANITIZE_ALL
ATTRIBUTE_TARGET_POPCNT
void __sanitizer_cov_trace_cmp1(uint8_t Arg1, uint8_t Arg2) {
  UInt PC = reinterpret_cast<UInt>(__builtin_return_address(0));
  fuzzer::TPC.HandleCmp(PC, Arg1, Arg2);
}

ATTRIBUTE_INTERFACE
ATTRIBUTE_NO_SANITIZE_ALL
ATTRIBUTE_TARGET_POPCNT
void __sanitizer_cov_trace_const_cmp1(uint8_t Arg1, uint8_t Arg2) {
  UInt PC = reinterpret_cast<UInt>(__builtin_return_address(0));
  fuzzer::TPC.HandleCmp(PC, Arg1, Arg2);
}

ATTRIBUTE_INTERFACE
ATTRIBUTE_NO_SANITIZE_ALL
ATTRIBUTE_TARGET_POPCNT
void __sanitizer_cov_trace_switch(uint64_t Val, uint64_t *Cases) {
  uint64_t N = Cases[0];
  uint64_t ValSizeInBits = Cases[1];
  uint64_t *Vals = Cases + 2;
  // Skip the most common and the most boring case.
  if (Vals[N - 1]  < 256 && Val < 256)
    return;
  UInt PC = reinterpret_cast<UInt>(__builtin_return_address(0));
  Int i;
  uint64_t Token = 0;
  for (i = 0; i < N; i++) {
    Token = Val ^ Vals[i];
    if (Val < Vals[i])
      break;
  }

  if (ValSizeInBits == 16)
    fuzzer::TPC.HandleCmp(PC + i, static_cast<uint16_t>(Token), (uint16_t)(0));
  else if (ValSizeInBits == 32)
    fuzzer::TPC.HandleCmp(PC + i, static_cast<uint32_t>(Token), (uint32_t)(0));
  else
    fuzzer::TPC.HandleCmp(PC + i, Token, (uint64_t)(0));
}

ATTRIBUTE_INTERFACE
ATTRIBUTE_NO_SANITIZE_ALL
ATTRIBUTE_TARGET_POPCNT
void __sanitizer_cov_trace_div4(uint32_t Val) {
  UInt PC = reinterpret_cast<UInt>(__builtin_return_address(0));
  fuzzer::TPC.HandleCmp(PC, Val, (uint32_t)0);
}

ATTRIBUTE_INTERFACE
ATTRIBUTE_NO_SANITIZE_ALL
ATTRIBUTE_TARGET_POPCNT
void __sanitizer_cov_trace_div8(uint64_t Val) {
  UInt PC = reinterpret_cast<UInt>(__builtin_return_address(0));
  fuzzer::TPC.HandleCmp(PC, Val, (uint64_t)0);
}

ATTRIBUTE_INTERFACE
ATTRIBUTE_NO_SANITIZE_ALL
ATTRIBUTE_TARGET_POPCNT
void __sanitizer_cov_trace_gep(UInt Idx) {
  UInt PC = reinterpret_cast<UInt>(__builtin_return_address(0));
  fuzzer::TPC.HandleCmp(PC, Idx, (UInt)0);
}

 */
