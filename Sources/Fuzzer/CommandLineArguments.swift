//
//  CommandLineArguments.swift
//  Fuzzer
//
//  Created by Loïc Lecrenier on 04/06/2018.
//

import Files
import Foundation
import Utility

let usage = "[options]"

let overview = """
FuzzCheck is an evolutionary in-process fuzzer for testing Swift programs.
Steps:
- read sample inputs from a list of input folders
- feed these inputs to a test Swift function
- analyze the code coverage triggered by each input
- the most interesting inputs are kept in an in-memory corpus
- then, repeatedly:
    - randomly select an input from the in-memory corpus
    - apply random mutations to that input
    - feed the mutated input to the test function
    - analyze the code coverage again
    - evaluate the usefulness of the mutated input
      and maybe add it to the in-memory corpus
    - repeat until a crash is found
"""

extension Double: ArgumentKind {
    public init(argument: String) throws {
        if let d = Double.init(argument) {
            self = d
        } else {
            throw ArgumentParserError.invalidValue(argument: argument, error: ArgumentConversionError.typeMismatch(value: argument, expectedType: Double.self))
        }
    }
    public static var completion: ShellCompletion {
        return ShellCompletion.none
    }
}
extension UInt: ArgumentKind {
    public init(argument: String) throws {
        if let d = UInt(argument) {
            self = d
        } else {
            throw ArgumentParserError.invalidValue(argument: argument, error: ArgumentConversionError.typeMismatch(value: argument, expectedType: UInt.self))
        }
    }
    public static var completion: ShellCompletion {
        return ShellCompletion.none
    }
}
extension Folder: ArgumentKind {
    public convenience init(argument: String) throws {
        try self.init(path: argument)
    }
    public static var completion: ShellCompletion {
        return ShellCompletion.filename
    }
}
extension File: ArgumentKind {
    public convenience init(argument: String) throws {
        try self.init(path: argument)
    }
    public static var completion: ShellCompletion {
        return ShellCompletion.filename
    }
}

extension Array: ArgumentKind where Element == ArtifactSchema.Name.Atom {
    public init(argument: String) throws {
        self = ArtifactSchema.Name.Atom.read(from: argument)
    }
    public static var completion: ShellCompletion {
        return ShellCompletion.none
    }
}

extension ArtifactSchema.Content: ArgumentKind {
    public init(argument: String) throws {
        self.init(features: argument.contains("features"),
                  coverageScore: argument.contains("coverage"),
                  hash: argument.contains("hash"),
                  complexity: argument.contains("complexity"),
                  kind: argument.contains("kind"))
    }
    public static var completion: ShellCompletion {
        return ShellCompletion.none
    }
}

extension CommandLineFuzzerWorldInfo {
    public static func argumentsParser() -> (ArgumentParser, ArgumentBinder<FuzzerSettings>, ArgumentBinder<CommandLineFuzzerWorldInfo>, ArgumentBinder<FuzzerManagerSettings>) {
        let parser = ArgumentParser(usage: usage, overview: overview)
        let settingsBinder = ArgumentBinder<FuzzerSettings>()
        let worldBinder = ArgumentBinder<CommandLineFuzzerWorldInfo>()
        let managerSettingsBinder = ArgumentBinder<FuzzerManagerSettings>()
        
        let maxNumberOfRuns = parser.add(
            option: "--max-number-of-runs",
            shortName: "-runs",
            kind: UInt.self,
            usage: "The number of fuzzer iterations to run before exiting",
            completion: nil
        )
        let maxComplexity = parser.add(
            option: "--max-complexity",
            shortName: "-cplx",
            kind: Double.self,
            usage: "The upper bound complexity of the test units",
            completion: nil
        )
        let mutationDepth = parser.add(
            option: "--mutation-depth",
            shortName: "-mut",
            kind: UInt.self,
            usage: "The number of consecutive mutations applied to a unit in a single iteration",
            completion: nil
        )
        let shuffleAtStartup = parser.add(
            option: "--shuffle-input-corpus",
            shortName: "-shf",
            kind: Bool.self,
            usage: "If set, shuffle the input corpus before reading it",
            completion: nil
        )
        let globalTimeout = parser.add(
            option: "--global-timeout",
            shortName: "-gtm",
            kind: UInt.self,
            usage: "The maximum number of seconds to run FuzzCheck before exiting",
            completion: nil
        )
        let iterationTimeout = parser.add(
            option: "--iteration-timeout",
            shortName: "-itm",
            kind: UInt.self,
            usage: "The maximum number of milliseconds the test function is allowed to take to process a single input",
            completion: nil
        )
        let inputCorpora = parser.add(
            option: "--input-folders",
            shortName: "-in-f",
            kind: Array<Folder>.self,
            usage: "List of folders containing JSON-encoded sample inputs to use as a starting point",
            completion: nil
        )
        let outputCorpus = parser.add(
            option: "--output-folder",
            shortName: "-out-f",
            kind: Folder.self,
            usage: "Folder in which to store the interesting inputs generated during the fuzzing process"
        )
        let artifactsFolder = parser.add(
            option: "--artifact-folder",
            shortName: "-art-f",
            kind: Folder.self,
            usage: "Folder in which to store the artifact generated at the end of the fuzzing process. Artifacts may be inputs that cause a crash, or inputs that took longer than <iteration-timeout> milliseconds to be tested"
        )
        let artifactFileName = parser.add(
            option: "--artifact-filename",
            shortName: "-art-name",
            kind: Array<ArtifactSchema.Name.Atom>.self,
            usage: "The name of the artifact"
        )
        let artifactFileExtension = parser.add(
            option: "--artifact-file-extension",
            shortName: "-art-ext",
            kind: String.self,
            usage: "The extension of the artifact"
        )
        let minimize = parser.add(
            option: "--minimize",
            shortName: nil,
            kind: Bool.self,
            usage: "If set, will run in minimize mode."
        )
        
        let minimizeFile = parser.add(
            option: "--minimize-file",
            shortName: nil,
            kind: File.self,
            usage: "If set, will try to minimize the given crashing input."
        )
        
        let seed = parser.add(
            option: "--seed",
            shortName: nil,
            kind: UInt.self,
            usage: "Seed for the pseudo-random number generator"
        )
        
        let target = parser.add(
            option: "--target",
            shortName: "-t",
            kind: String.self,
            usage: "The executable containing the fuzzer loop",
            completion: nil
        )
        
        settingsBinder.bind(option: maxNumberOfRuns) { $0.maxNumberOfRuns = Int($1) }
        settingsBinder.bind(option: maxComplexity) { $0.maxUnitComplexity = Complexity($1) }
        settingsBinder.bind(option: mutationDepth) { $0.mutateDepth = Int($1) }
        settingsBinder.bind(option: shuffleAtStartup) { $0.shuffleAtStartup = $1 }
        settingsBinder.bind(option: iterationTimeout) { $0.iterationTimeout = $1 }
        settingsBinder.bind(option: minimize) { $0.minimize = $1 }
        
        worldBinder.bind(option: inputCorpora) { $0.inputCorpora = $1 }
        worldBinder.bind(option: outputCorpus) { $0.outputCorpus = $1 }
        worldBinder.bind(option: artifactsFolder) { $0.artifactsFolder = $1 }
        worldBinder.bind(option: artifactFileName) { $0.artifactsNameSchema.atoms = $1 }
        worldBinder.bind(option: artifactFileExtension) { $0.artifactsNameSchema.ext = $1 }
        worldBinder.bind(option: seed) { $0.rand = Rand(seed: UInt32($1)) }
        
        managerSettingsBinder.bind(option: target) { $0.testExecutable = try getExecutableFile().parent!.file(named: $1) }
        managerSettingsBinder.bind(option: minimizeFile) { $0.minimizeFile = $1 }
        managerSettingsBinder.bind(option: globalTimeout) { $0.globalTimeout = $1 }
        
        return (parser, settingsBinder, worldBinder, managerSettingsBinder)
    }
}

public struct FuzzerManagerSettings {
    public var testExecutable: File? = nil
    public var minimizeFile: File? = nil
    public var globalTimeout: UInt? = nil
    public init() { }
}

extension FuzzerManagerSettings {
    public var commandLineArguments: [String] {
        var args: [String] = []
        if let exec = testExecutable { args += ["--target", exec.path] }
        if let minFile = minimizeFile { args += ["--minimize-file", minFile.path] }
        if let gtm = globalTimeout { args += ["--global-timeout", "\(gtm)"] }
        return args
    }
}

extension FuzzerSettings {
    public var commandLineArguments: [String] {
        var args: [String] = []
        args += ["--max-complexity", "\(maxUnitComplexity)"]
        if minimize { args.append("--minimize") }
        args += ["--iteration-timeout", "\(iterationTimeout)"]
        args += ["--max-number-of-runs", "\(maxNumberOfRuns)"]
        args += ["--mutation-depth", "\(mutateDepth)"]
        if shuffleAtStartup { args.append("--shuffle-input-corpus") }
        return args
    }
}

extension CommandLineFuzzerWorldInfo {
    public var commandLineArguments: [String] {
        var args: [String] = []
        args += ["--seed", "\(rand.seed)"]
        args += ["--artifact-folder", "\(artifactsFolder.path)"]
        args += ["--artifact-filename", "\(artifactsNameSchema.atoms.map { $0.description }.joined())"]
        if let ext = artifactsNameSchema.ext { args += ["--artifact-file-extension", "\(ext)"] }
        if !inputCorpora.isEmpty {
            args.append("--input-folders")
            args += inputCorpora.map { $0.path }
        }
        if let out = outputCorpus { args += ["--output-folder", "\(out.path)"] }
        return args
    }
}

func getExecutableFile() throws -> File {
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
    return try File(path: path)
}
