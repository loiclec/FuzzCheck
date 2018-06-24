
import Basic
import Files
import Foundation
import Fuzzer
import Utility

typealias Process = Foundation.Process
typealias URL = Foundation.URL

let lock = Lock()

let (parser, workerSettingsBinder, worldBinder, settingsBinder) = CommandLineFuzzerWorldInfo.argumentsParser()
do {
    let res = try parser.parse(Array(CommandLine.arguments.dropFirst()))
    var workerSettings: FuzzerSettings = FuzzerSettings()
    try workerSettingsBinder.fill(parseResult: res, into: &workerSettings)
    
    var settings = FuzzerManagerSettings()
    try settingsBinder.fill(parseResult: res, into: &settings)
    guard let exec = settings.testExecutable else {
        fatalError()
    }
    
    var fuzzerJobEnvironment = ProcessInfo.processInfo.environment
    fuzzerJobEnvironment["SWIFT_DETERMINISTIC_HASHING"] = "1"
    var process = Process()
    let launchPath = exec.path
    let environment = fuzzerJobEnvironment
    var arguments = Array(CommandLine.arguments.dropFirst())
    
    print(workerSettings)
    
    let signals: [Signal] = [.segmentationViolation, .busError, .abort, .illegalInstruction, .floatingPointException, .interrupt, .softwareTermination, .fileSizeLimitExceeded]
    
    let sh = SignalsHandler(signals: signals) { signal in
        lock.withLock {
            print("Received signal \(signal)")
            if process.isRunning {
                process.interrupt()
                print("Sent interrupt signal to process \(process.processIdentifier) (\(process.launchPath!)")
                // Give the child process a maximum of two seconds to shut down
                sleep(2)
                if process.isRunning { _ = process.suspend() }
            }
            exit(0)
        }
    }
    
    let timerSource = DispatchSource.makeTimerSource(flags: .strict, queue: DispatchQueue.global())
    if let globalTimeout = settings.globalTimeout {
        // set up timer
        
        let time: DispatchTime = DispatchTime(uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds + UInt64(globalTimeout) * 1_000_000_000)
        timerSource.schedule(deadline: time)
        timerSource.setEventHandler {
            if process.isRunning {
                process.interrupt()
                print("Process interrupted because of global timeout.")
                sleep(2)
                
                if process.isRunning { _  = process.suspend() }
            }
            exit(0)
        }
        timerSource.activate()
    }
    
    if let fileToMinimize = settings.minimizeFile {
        var world = CommandLineFuzzerWorldInfo()
        try worldBinder.fill(parseResult: res, into: &world)
        
        let inputFolder = try fileToMinimize.parent!.createSubfolderIfNeeded(withName: fileToMinimize.nameExcludingExtension + ".minimized")
        try inputFolder.createFileIfNeeded(withName: fileToMinimize.name).write(data: fileToMinimize.read())
        world.inputCorpora = [inputFolder]
        world.artifactsFolder = inputFolder
        //world.artifactsNameSchema.atoms = ArtifactSchema.Name.Atom.read(from: "?complexity.?hash")
        workerSettings.minimize = true
        
        arguments = workerSettings.commandLineArguments + world.commandLineArguments
        while true {
            do {
                lock.withLock {
                    process = Process()
                }
                process.launchPath = launchPath
                process.environment = environment
                process.arguments = arguments
                try process.run()
                process.waitUntilExit()
            } catch let e {
                print(e)
                exit(1)
            }
        }
        
    } else {
        do {
            lock.withLock {
                process = Process()
            }
            process.launchPath = launchPath
            process.environment = environment
            process.arguments = arguments
            try process.run()
            process.waitUntilExit()
        } catch let e {
            print(e)
            exit(1)
        }
    }

    withExtendedLifetime(sh) { }
    withExtendedLifetime(timerSource) { }
} catch let e {
    print(e)
    parser.printUsage(on: stdoutStream)
}
