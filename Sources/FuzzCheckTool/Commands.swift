//
//  Commands.swift
//  FuzzCheckJobsManager
//

import Basic
import Files
import Foundation
import FuzzCheck
import Utility

/// A wrapper type with reference semantics
class Ref <T> {
    var data: T
    
    init(_ data: T) { self.data = data }
}

/// Lock used to synchronize the launches of the child process with the interrupt/timer
/// signal handlers. We don't want to launch an additional child process while we are
/// shutting down the program.
/// documentation reference: #wupKfXxNqM8
let childProcessLock = Lock()

/// Return a reference to the child process as well as the properties needed to launch it.
func childProcessInfo(settings: FuzzerManagerSettings) -> (ref: Ref<Process>, launchPath: String, env: [String: String]) {
    let exec = settings.testExecutable!
    var fuzzerJobEnvironment = ProcessInfo.processInfo.environment
    fuzzerJobEnvironment["SWIFT_DETERMINISTIC_HASHING"] = "1"
    let process = Ref(Process())
    let launchPath = exec.path
    let environment = fuzzerJobEnvironment
    
    return (process, launchPath, environment)
}

func minimizeCommand(settings: FuzzerManagerSettings, workerSettings: FuzzerSettings, world: CommandLineFuzzerWorldInfo) throws -> Never {
    var (settings, workerSettings, world) = (settings, workerSettings, world)
    
    let fileToMinimize = world.inputFile! // TODO: put that requirement in the arguments parser
    let (process, launchPath, environment) = childProcessInfo(settings: settings)
    let (sh, timerSource) = signalHandlers(process: process, globalTimeout: settings.globalTimeout)
    
    // The child processes will create artifacts, we put them all under a folder named <fileToMinimize>.minimized
    // We will launch the child process with the simplest input file in that folder as argument.
    // That folder might already exist (because of a previous minimization attempt). In that case we do nothing.
    let artifactsFolder = try fileToMinimize.parent!.createSubfolderIfNeeded(withName: fileToMinimize.nameExcludingExtension + ".minimized")
    
    world.artifactsFolder = artifactsFolder
    // we store the complexity in the artifacts file so that we can determine which artifact is the simplest one.
    world.artifactsContentSchema = .init(features: false, coverageScore: false, hash: false, complexity: true, kind: false)
    // the complexity in the artifact files is stored under the key “complexity”
    // we create this simple wrapper type to decode it
    /** e.g.
     {
        input: {...},
        complexity: 23.3
     }
    */
    struct Complexity: Decodable {
        let complexity: Double
    }
    
    /// Return the artifact file containing the simplest input, or nil if the artifacts folder is empty
    func simplestInputFile() -> File? {
        let filesWithComplexity = artifactsFolder.files.map { f -> (File, Double) in
            (f, try! JSONDecoder().decode(Complexity.self, from: f.read()).complexity)
        }
        return filesWithComplexity.min { $0.1 < $1.1 }?.0
    }
    
    world.inputFile = simplestInputFile() ?? fileToMinimize
    
    workerSettings.command = .read
    world.artifactsFolder = artifactsFolder.containsFile(named: world.inputFile!.name) ? nil : artifactsFolder

    try run(process: process, launchPath: launchPath, arguments: workerSettings.commandLineArguments + world.commandLineArguments, env: environment)
    
    precondition(process.data.terminationStatus == FuzzerTerminationStatus.crash.rawValue || process.data.terminationStatus == FuzzerTerminationStatus.testFailure.rawValue, "The input to minimize didn't cause a crash")
    
    workerSettings.command = .minimize
    world.artifactsFolder = artifactsFolder
    
    // TODO: max number of runs
    while true {
        // By now we have added at least one file to the artifacts folder, so simplestInputFile() cannot be nil
        world.inputFile = simplestInputFile()!

        try run(process: process, launchPath: launchPath, arguments: workerSettings.commandLineArguments + world.commandLineArguments, env: environment)

        withExtendedLifetime(sh) { }
        withExtendedLifetime(timerSource) { }
    }
}

func fuzzCommand(settings: FuzzerManagerSettings, workerSettings: FuzzerSettings, world: CommandLineFuzzerWorldInfo) throws -> Never {
 
    let (process, launchPath, environment) = childProcessInfo(settings: settings)
    let (sh, timerSource) = signalHandlers(process: process, globalTimeout: settings.globalTimeout)
    
    try run(process: process, launchPath: launchPath, arguments: workerSettings.commandLineArguments + world.commandLineArguments, env: environment)

    withExtendedLifetime(sh) { }
    withExtendedLifetime(timerSource) { }
    
    exit(0)
}

func run(process: Ref<Process>, launchPath: String, arguments: [String], env: [String: String]) throws {
    // see: #wupKfXxNqM8
    childProcessLock.withLock {
        process.data = Process()
    }
    let process = process.data
    process.launchPath = launchPath
    process.environment = env
    process.arguments = arguments
    if #available(OSX 10.13, *) {
        try process.run()
    } else {
        process.launch()
    }
    process.waitUntilExit()
}

/// Shut down the given process. First send an interrupt signal, then
/// force-suspend it if it didn't process the interrupt quickly enough.
func interrupt(_ process: Ref<Process>) {
    // can't interrupt a process that is not running
    guard process.data.isRunning else { return }
    // Send interrupt signal
    process.data.interrupt()
    // Give the child process 0.1 seconds to exit
    Foundation.Thread.sleep(forTimeInterval: 0.1)
    
    // If child process has not exited yet
    if process.data.isRunning {
        // Give the child process an additional two seconds to exit
        Foundation.Thread.sleep(forTimeInterval: 2.0)
        // If it is *still* running, then
        if process.data.isRunning {
            // force-suspend it
            _ = process.data.suspend()
        }
    }
}

/**
 Create the interrupt signal handler and the Dispatch source timer.
 These two objects are responsible for stopping the child processes and
 the program itself.
 */
func signalHandlers(process: Ref<Process>, globalTimeout: UInt?) -> (SignalsHandler, DispatchSourceTimer) {
    
    let signals: [Signal] = [.segmentationViolation, .busError, .abort, .illegalInstruction, .floatingPointException, .interrupt, .softwareTermination, .fileSizeLimitExceeded]
    
    let sh = SignalsHandler(signals: signals) { signal in
        // Another part of the program might want to relaunch the process as soon as we
        // interrupt it, so we guard process creation/interrupt operations under a common lock.
        // see: #wupKfXxNqM8
        childProcessLock.withLock {
            interrupt(process)
            exit(0)
        }
    }
    
    let timerSource = DispatchSource.makeTimerSource(flags: .strict, queue: DispatchQueue.global())
    if let globalTimeout = globalTimeout {
        let time: DispatchTime = DispatchTime(uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds + UInt64(globalTimeout) * 1_000_000_000)
        timerSource.schedule(deadline: time)
        timerSource.setEventHandler {
            // Another part of the program might want to relaunch the process as soon as we
            // interrupt it, so we guard process creation/interrupt operations under a common lock.
            // see: #wupKfXxNqM8
            childProcessLock.withLock {
                interrupt(process)
                exit(0)
            }
        }
        if #available(OSX 10.12, *) {
            timerSource.activate()
        } else {
            timerSource.resume()
        }
    }
    
    return (sh, timerSource)
}
