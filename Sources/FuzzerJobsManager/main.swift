
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
    
    var world = CommandLineFuzzerWorldInfo()
    try worldBinder.fill(parseResult: res, into: &world)

    if case .minimize = workerSettings.command, let fileToMinimize = world.inputFile {
        
        let inputFolder = try fileToMinimize.parent!.createSubfolderIfNeeded(withName: fileToMinimize.nameExcludingExtension + ".minimized")
        let data = try fileToMinimize.read()
        try inputFolder.createFileIfNeeded(withName: fileToMinimize.name, contents: data)
        
        world.artifactsFolder = inputFolder
        world.inputFile = fileToMinimize
        world.artifactsContentSchema = .init(features: false, coverageScore: false, hash: false, complexity: true, kind: false)
        
        struct Complexity: Decodable {
            let complexity: Double
        }
        
        while true {
            
            TRY: do {
                let filesWithComplexity = try inputFolder.files.map { f -> (File, Double) in
                    let data = try f.read()
                    let decoder = JSONDecoder()
                    let c = try decoder.decode(Complexity.self, from: data)
                    return (f, c.complexity)
                }
                world.inputFile = filesWithComplexity.min(by: { $0.1 < $1.1 })!.0
            } catch let e {
                if world.inputFile == fileToMinimize {
                    break TRY
                } else {
                    throw e
                }
            }
            
            if inputFolder.files.contains(world.inputFile!) {
                world.artifactsFolder = nil
            }
            workerSettings.command = .read
            arguments = workerSettings.commandLineArguments + world.commandLineArguments

            do {
                lock.withLock {
                    process = Process()
                }
                print("Will try to minimize \(world.inputFile!.name)")
                process.launchPath = launchPath
                process.environment = environment
                process.arguments = arguments
                print(process.arguments?.joined(separator: " ") ?? "")
                try process.run()
                process.waitUntilExit()
            } catch let e {
                print(e)
                exit(1)
            }
            guard process.terminationStatus == FuzzerTerminationStatus.crash.rawValue else {
                fatalError("The input to minimize didn't cause a crash")
            }
            
            workerSettings.command = .minimize
            world.inputCorpora = [inputFolder]
            world.artifactsFolder = inputFolder
            arguments = workerSettings.commandLineArguments + world.commandLineArguments

            do {
                lock.withLock {
                    process = Process()
                }
                process.launchPath = launchPath
                process.environment = environment
                process.arguments = arguments
                print(process.arguments?.joined(separator: " ") ?? "")
                try process.run()
                process.waitUntilExit()
            } catch let e {
                print(e)
                exit(1)
            }
        }
        
    } else if case .fuzz = workerSettings.command {
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
    } else {
        fatalError("Unsupported command")
    }

    withExtendedLifetime(sh) { }
    withExtendedLifetime(timerSource) { }
} catch let e {
    print(e)
    parser.printUsage(on: stdoutStream)
}
