//
//  CommandLineArguments.swift
//  Fuzzer
//
//  Created by Loïc Lecrenier on 04/06/2018.
//

import Files
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

extension FuzzerInfo where World == CommandLineFuzzerWorld<T> {

    public static func argumentsParser() -> (ArgumentParser, ArgumentBinder<FuzzerSettings>, ArgumentBinder<World>) {
        let parser = ArgumentParser(usage: usage, overview: overview)
        let settingsBinder = ArgumentBinder<FuzzerSettings>()
        let worldBinder = ArgumentBinder<World>()
        
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
            shortName: "-if",
            kind: Array<Folder>.self,
            usage: "List of folders containing JSON-encoded sample inputs to use as a starting point",
            completion: nil
        )
        let outputCorpus = parser.add(
            option: "--output-folder",
            shortName: "-of",
            kind: Folder.self,
            usage: "Folder in which to store the interesting inputs generated during the fuzzing process"
        )
        let artifactsFolder = parser.add(
            option: "--artifact-folder",
            shortName: "-af",
            kind: Folder.self,
            usage: "Folder in which to store the artifact generated at the end of the fuzzing process. Artifacts may be inputs that cause a crash, or inputs that took longer than <iteration-timeout> milliseconds to be tested"
        )
        let seed = parser.add(
            option: "--seed",
            shortName: nil,
            kind: UInt.self,
            usage: "Seed for the pseudo-random number generator"
        )
        
        settingsBinder.bind(option: maxNumberOfRuns) { $0.maxNumberOfRuns = Int($1) }
        settingsBinder.bind(option: maxComplexity) { $0.maxUnitComplexity = Complexity($1) }
        settingsBinder.bind(option: mutationDepth) { $0.mutateDepth = Int($1) }
        settingsBinder.bind(option: shuffleAtStartup) { $0.shuffleAtStartup = $1 }
        settingsBinder.bind(option: globalTimeout) { $0.globalTimeout = $1 }
        settingsBinder.bind(option: iterationTimeout) { $0.iterationTimeout = $1 }
        
        worldBinder.bind(option: inputCorpora) { $0.inputCorpora = $1 }
        worldBinder.bind(option: outputCorpus) { $0.outputCorpus = $1 }
        worldBinder.bind(option: artifactsFolder) { $0.artifactsFolder = $1 }
        worldBinder.bind(option: seed) { $0.rand = Rand(seed: UInt32($1)) }
        
        return (parser, settingsBinder, worldBinder)
    }    
}
