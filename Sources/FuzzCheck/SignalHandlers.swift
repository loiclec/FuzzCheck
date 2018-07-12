

import Foundation
import Basic

typealias Thread = Basic.Thread

/// Interrupt signal handling global variables
private var receivedSignal: Signal? = nil

private var signalSemaphore = DispatchSemaphore(value: 0)
private var writeSignalSemaphore = DispatchSemaphore(value: 1)

private var oldActions = Array<sigaction>.init(repeating: sigaction(), count: 32)

/// This class can be used by command line tools to install a handler which
/// should be called when a interrupt signal is delivered to the process.
public final class SignalsHandler {
    
    /// The thread which waits to be notified when a signal is received.
    let thread: Thread
    
    let signals: [Signal]
    
    /// Start watching for interrupt signal and call the handler whenever the signal is received.
    public init(signals: [Signal], handler: @escaping (Signal) -> Void) {
        self.signals = signals
        // Create a signal handler.
        let signalHandler: @convention(c)(Int32) -> Void = { sig in
            writeSignalSemaphore.wait()
            receivedSignal = Signal(rawValue: sig)!
            signalSemaphore.signal()
        }
        var action = sigaction()
        action.__sigaction_u.__sa_handler = signalHandler
        for signal in signals {
            // Install the new handler.
            let result = sigaction(signal.rawValue, &action, &oldActions[Int(signal.rawValue)])
            precondition(result == 0)
        }
        
        // This thread waits to be notified via semaphore.
        thread = Thread {
            while true {
                signalSemaphore.wait()
                if let _receivedSignal = receivedSignal {
                    handler(_receivedSignal)
                    receivedSignal = nil
                } else { // if the signal semaphore was signaled but no received signal exists, then
                         // it means the Thread should finish its execution
                    return
                }
                writeSignalSemaphore.signal()
            }
        }
        thread.start()
    }
    
    deinit {
        for sig in signals {
            // Restore the old action and close the write end of pipe.
            sigaction(sig.rawValue, &oldActions[Int(sig.rawValue)], nil)
        }
        receivedSignal = nil
        signalSemaphore.signal()
        thread.join()
    }
}

public enum Signal: Int32 {
    case terminalLineHangup = 1
    case interrupt
    case quit
    case illegalInstruction
    case traceTrap
    case abort
    case emulateInstructionExecuted
    case floatingPointException
    case kill
    case busError
    case segmentationViolation
    case nonExistentSystemCallInvoked
    case writeOnPipeWithNoReader
    case realTimeTimerExpired
    case softwareTermination
    case urgentConditionOnSocket
    case uncatchableStop
    case keyboardStop
    case continueAfterStop
    case childStatusHasChanged
    case backgroundReadAttemptedFromControlTerminal
    case backgroundWriteAttemptedToControlTerminal
    case ioPossibleOnADescriptor
    case cpuTimeLimitExceeded
    case fileSizeLimitExceeded
    case virtualTimeAlarm
    case profilingTimerAlarm
    case windowSizeChange
    case statusRequestFromKeyboard
    case userDefined1
    case userDefined2
    
    /*
     1     SIGHUP       terminate process    terminal line hangup
     2     SIGINT       terminate process    interrupt program
     3     SIGQUIT      create core image    quit program
     4     SIGILL       create core image    illegal instruction
     5     SIGTRAP      create core image    trace trap
     6     SIGABRT      create core image    abort program (formerly SIGIOT)
     7     SIGEMT       create core image    emulate instruction executed
     8     SIGFPE       create core image    floating-point exception
     9     SIGKILL      terminate process    kill program
     10    SIGBUS       create core image    bus error
     11    SIGSEGV      create core image    segmentation violation
     12    SIGSYS       create core image    non-existent system call invoked
     13    SIGPIPE      terminate process    write on a pipe with no reader
     14    SIGALRM      terminate process    real-time timer expired
     15    SIGTERM      terminate process    software termination signal
     16    SIGURG       discard signal       urgent condition present on socket
     17    SIGSTOP      stop process         stop (cannot be caught or ignored)
     18    SIGTSTP      stop process         stop signal generated from keyboard
     19    SIGCONT      discard signal       continue after stop
     20    SIGCHLD      discard signal       child status has changed
     21    SIGTTIN      stop process         background read attempted from control terminal
     22    SIGTTOU      stop process         background write attempted to control  terminal
     23    SIGIO        discard signal       I/O is possible on a descriptor (see fcntl(2))
     24    SIGXCPU      terminate process    cpu time limit exceeded (see setrlimit(2))
     25    SIGXFSZ      terminate process    file size limit exceeded (see setrlimit(2))
     26    SIGVTALRM    terminate process    virtual time alarm (see setitimer(2))
     27    SIGPROF      terminate process    profiling timer alarm (see setitimer(2))
     28    SIGWINCH     discard signal       Window size change
     29    SIGINFO      discard signal       status request from keyboard
     30    SIGUSR1      terminate process    User defined signal 1
     31    SIGUSR2      terminate process    User defined signal 2
     */
}

