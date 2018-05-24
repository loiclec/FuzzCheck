
import Darwin

var coordinator = Coordinator()

struct Coordinator {
    enum Signal {
        case alarm
        case crash
        case fileSizeExceed
        case interrupt
    }
    var _send: ((Signal) -> Void)?
    func send(s: Signal) {
        if let _send = _send {
            _send(s)
        }
    }
}

func setTimer(microseconds: Int32) {
    var t = itimerval.init(it_interval: .init(tv_sec: 1, tv_usec: 0), it_value: .init(tv_sec: 1, tv_usec: 0))
    if setitimer(ITIMER_REAL, &t, nil) != 0 {
        print("libFuzzer: setitimer failed with \(errno)")
        exit(1)
    }
    setSigAction(SIGALRM, alarmHandler)
}

func setSignalHandler(timeout: Int) {
    setTimer(microseconds: Int32(timeout))
    setSigAction(SIGSEGV, crashHandler)
    setSigAction(SIGBUS, crashHandler)
    setSigAction(SIGABRT, crashHandler)
    setSigAction(SIGILL, crashHandler)
    setSigAction(SIGFPE, crashHandler)
    setSigAction(SIGINT, interruptHandler)
    setSigAction(SIGTERM, interruptHandler)
    setSigAction(SIGXFSZ, fileSizeExceedHandler)
}

func alarmHandler(_ x: Int32, _ s: UnsafeMutablePointer<__siginfo>?, _ p: UnsafeMutableRawPointer?) -> Void {
    coordinator.send(s: .alarm)
}
func crashHandler(_ x: Int32, _ s: UnsafeMutablePointer<__siginfo>?, _ p: UnsafeMutableRawPointer?) -> Void {
    coordinator.send(s: .crash)
}
func interruptHandler(_ x: Int32, _ s: UnsafeMutablePointer<__siginfo>?, _ p: UnsafeMutableRawPointer?) -> Void {
    coordinator.send(s: .interrupt)
}
func fileSizeExceedHandler(_ x: Int32, _ s: UnsafeMutablePointer<__siginfo>?, _ p: UnsafeMutableRawPointer?) -> Void {
    coordinator.send(s: .interrupt)
}

func setSigAction(_ signum: Int32, _ callback: (@convention(c) (Int32, UnsafeMutablePointer<__siginfo>?, UnsafeMutableRawPointer?) -> Void)!) {
    var sigact: sigaction = .init()
    if sigaction(signum, nil, &sigact) != 0 {
        print("libFuzzer: sigaction failed with \(errno)")
        exit(1)
    }
    if (sigact.sa_flags & SA_SIGINFO) != 0 {
        guard sigact.__sigaction_u.__sa_sigaction == nil else { return }
    } else {
        guard [SIG_DFL, SIG_IGN, SIG_ERR].contains(where: { bytesOf($0) == bytesOf(sigact.__sigaction_u.__sa_handler) }) else { return }
    }
    sigact = .init()
    sigact.__sigaction_u.__sa_sigaction = callback
    if sigaction(signum, &sigact, nil) != 0 {
        print("libFuzzer: sigaction failed with \(errno)")
        exit(1)
    }
}

func bytesOf <T> (_ t: T) -> [UInt8] {
    let ptr = UnsafeMutablePointer<T>.allocate(capacity: 1)
    ptr.initialize(to: t)
    let rawptr = UnsafeRawPointer(ptr)
    let buffer = UnsafeRawBufferPointer(start: rawptr, count: MemoryLayout<sig_t>.size)
    return Array(buffer)
}
