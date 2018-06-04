
import Foundation
import Fuzzer
import Utility

typealias URL = Foundation.URL

let fuzzTestName = CommandLine.arguments[1]

var fuzzerJobEnvironment = ProcessInfo.processInfo.environment
fuzzerJobEnvironment["SWIFT_DETERMINISTIC_HASHING"] = "1"

func getExecutablePath() -> URL {
    var cPath: UnsafeMutablePointer<Int8> = UnsafeMutablePointer.allocate(capacity: 1)
    var size: UInt32 = 1
    defer { cPath.deallocate() }
    
    Loop: while true {
        let result = _NSGetExecutablePath(cPath, &size)
        switch result {
        case 0:
            break Loop
        case -1:
            cPath.deallocate()
            cPath = UnsafeMutablePointer.allocate(capacity: Int(size))
        default:
            fatalError("Failed to get an executable path to the current process.")
        }
    }
    
    let path = String(cString: cPath)
    return URL (fileURLWithPath: path)
}

let selfExecutableURL = getExecutablePath()

let workerExecutableURL = selfExecutableURL.deletingLastPathComponent().appendingPathComponent(fuzzTestName)

let process = Process.init()
process.launchPath = workerExecutableURL.path
process.environment = fuzzerJobEnvironment

process.launch()

let pid = process.processIdentifier

let source = DispatchSource.makeProcessSource(identifier: process.processIdentifier, eventMask: .exit)
source.setEventHandler(handler: {
    print("exit event received")
    exit(1)
})
source.setRegistrationHandler(handler: {
    print("source registered")
})
source.resume()

/*
let source3 = DispatchSource.makeTimerSource()
source3.schedule(deadline: DispatchTime.distantFuture, repeating: DispatchTimeInterval.milliseconds(100), leeway: DispatchTimeInterval.milliseconds(10))

source3.setEventHandler {
    process.suspend()
    print("process suspended for 2 seconds")
    sleep(2)
    print("process will start again")
    process.resume()
}
source3.resume()
*/

let signals: [Signal] = [.segmentationViolation, .busError, .abort, .illegalInstruction, .floatingPointException, .interrupt, .softwareTermination, .fileSizeLimitExceeded]

let sh = SignalsHandler(signals: signals) { signal in
    print("Received signal \(signal)")

    process.interrupt()
    print("Sent interrupt signal to process \(process.processIdentifier) (\(process.launchPath!)")
    // Give the child process a maximum of two seconds to shut down
    sleep(2)
    _ = process.suspend()
    exit(1)
}

process.waitUntilExit()
print("exited!")
sleep(1000)

withExtendedLifetime(sh) { }


