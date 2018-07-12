
import Darwin
import Foundation
import CBuiltinsNotAvailableInSwift

/**
 Normalize the value of a program counter so that it doesn't vary
 between runs of the same program.
*/
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
func trace_pc_guard(g: UnsafeMutablePointer<UInt32>?) {
    guard CodeCoverageSensor.shared.isRecording, let g = g else { return }
    let idx = Int(g.pointee)
    // TODO: could this be guarded by a lock, or would it ruin performance?
    // TODO: is the overflow check important, or could I let it overflow?
    let (result, overflow) = CodeCoverageSensor.shared.eightBitCounters[idx].addingReportingOverflow(1)
    if !overflow {
        CodeCoverageSensor.shared.eightBitCounters[idx] = result
    }
}

@_cdecl("__sanitizer_cov_trace_pc_guard_init")
func trace_pc_guard_init(start: UnsafeMutablePointer<UInt32>, stop: UnsafeMutablePointer<UInt32>) {
    CodeCoverageSensor.shared.handlePCGuardInit(start: start, stop: stop)
}

@_cdecl("__sanitizer_cov_trace_pc_indir")
func trace_pc_indir(callee: PC) {
    guard CodeCoverageSensor.shared.isRecording else { return }

    let caller = PC(bitPattern: __return_address())
    CodeCoverageSensor.shared.handlePCIndir(caller: NormalizedPC(caller), callee: NormalizedPC(callee))
}

@_cdecl("__sanitizer_cov_trace_cmp8")
func trace_cmp8(arg1: UInt64, arg2: UInt64) {
    guard CodeCoverageSensor.shared.isRecording else { return }
    let pc = NormalizedPC(PC(bitPattern: __return_address()))
    CodeCoverageSensor.shared.handleTraceCmp(pc: pc, arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_const_cmp8")
func trace_const_cmp8(arg1: UInt64, arg2: UInt64) {
    guard CodeCoverageSensor.shared.isRecording else { return }
    let pc = PC(bitPattern: __return_address())
    let x = NormalizedPC(pc)
    CodeCoverageSensor.shared.handleTraceCmp(pc: x, arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_cmp4")
func trace_cmp4(arg1: UInt32, arg2: UInt32) {
    guard CodeCoverageSensor.shared.isRecording else { return }

    let pc = PC(bitPattern: __return_address())
    CodeCoverageSensor.shared.handleTraceCmp(pc: NormalizedPC(pc), arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_const_cmp4")
func trace_const_cmp4(arg1: UInt32, arg2: UInt32) {
    guard CodeCoverageSensor.shared.isRecording else { return }

    let pc = PC(bitPattern: __return_address())
    CodeCoverageSensor.shared.handleTraceCmp(pc: NormalizedPC(pc), arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_cmp2")
func trace_cmp2(arg1: UInt16, arg2: UInt16) {
    guard CodeCoverageSensor.shared.isRecording else { return }

    let pc = PC(bitPattern: __return_address())
    CodeCoverageSensor.shared.handleTraceCmp(pc: NormalizedPC(pc), arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_const_cmp2")
func trace_const_cmp2(arg1: UInt16, arg2: UInt16) {
    guard CodeCoverageSensor.shared.isRecording else { return }

    let pc = PC(bitPattern: __return_address())
    CodeCoverageSensor.shared.handleTraceCmp(pc: NormalizedPC(pc), arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_cmp1")
func trace_cmp1(arg1: UInt8, arg2: UInt8) {
    guard CodeCoverageSensor.shared.isRecording else { return }

    let pc = PC(bitPattern: __return_address())
    CodeCoverageSensor.shared.handleTraceCmp(pc: NormalizedPC(pc), arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_const_cmp1")
func trace_const_cmp1(arg1: UInt8, arg2: UInt8) {
    guard CodeCoverageSensor.shared.isRecording else { return }
    let pc = PC(bitPattern: __return_address())
    CodeCoverageSensor.shared.handleTraceCmp(pc: NormalizedPC(pc), arg1: arg1, arg2: arg2)
}

@_cdecl("__sanitizer_cov_trace_switch")
func trace_switch(val: UInt64, cases: UnsafePointer<UInt64>) {
    guard CodeCoverageSensor.shared.isRecording else { return }

    // TODO: this was copied from libFuzzer and I never bothered understanding it
    // - why is `!(vals[Int(n - 1)] < 256 && val < 256)` “the most common and boring case”?
    // - why do I handle switches the same way as comparison operations?
    
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

    CodeCoverageSensor.shared.handleTraceCmp(pc: NormalizedPC(pc + UInt(i)), arg1: token, arg2: 0)
}

@_cdecl("__sanitizer_cov_trace_div4")
func trace_div4(val: UInt32) {
    guard CodeCoverageSensor.shared.isRecording else { return }

    let pc = PC(bitPattern: __return_address())
    CodeCoverageSensor.shared.handleTraceCmp(pc: NormalizedPC(pc), arg1: val, arg2: 0)
}

@_cdecl("__sanitizer_cov_trace_div8")
func trace_div8(val: UInt64) {
    guard CodeCoverageSensor.shared.isRecording else { return }

    let pc = PC(bitPattern: __return_address())
    CodeCoverageSensor.shared.handleTraceCmp(pc: NormalizedPC(pc), arg1: val, arg2: 0)
}
