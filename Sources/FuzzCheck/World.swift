//
//  World.swift
//  FuzzCheck
//
//  Created by Loïc Lecrenier on 03/06/2018.
//

import Files
import Foundation

/// An fuzzer event to communicate with the world
public enum FuzzerEvent {
    /// The fuzzing process started
    case start
    /// The fuzzing process ended
    case done
    /// A new interesting input was discovered
    case new
    /// The initial corpus has been process
    case didReadCorpus
    /// A signal sent to the process was caught
    case caughtSignal(Signal)
    /// A test failure was found
    case testFailure
}

public protocol FuzzerWorld {
    associatedtype Input
    associatedtype Properties: FuzzerInputProperties where Properties.Input == Input
    associatedtype Feature: Codable
    
    mutating func getPeakMemoryUsage() -> UInt
    mutating func clock() -> UInt
    mutating func readInputCorpus() throws -> [Input]
    mutating func readInputFile() throws -> Input
    
    mutating func saveArtifact(input: Input, features: [Feature]?, score: Double?, kind: ArtifactKind) throws
    mutating func addToOutputCorpus(_ input: Input) throws
    mutating func removeFromOutputCorpus(_ input: Input) throws
    mutating func reportEvent(_ event: FuzzerEvent, stats: FuzzerStats)
    
    var rand: FuzzerPRNG { get set }
}

public struct FuzzerStats {
    public var totalNumberOfRuns: Int = 0
    public var score: Double = 0
    public var poolSize: Int = 0
    public var executionsPerSecond: Int = 0
    public var rss: Int = 0
}

public struct FuzzerSettings {
    
    public enum Command: String {
        case minimize
        case fuzz
        case read
    }
    
    public var command: Command
    public var maxNumberOfRuns: Int
    public var maxInputComplexity: Double
    public var mutateDepth: Int
    
    public init(command: Command = .fuzz, maxNumberOfRuns: Int = Int.max, maxInputComplexity: Double = 256.0, mutateDepth: Int = 3) {
        self.command = command
        self.maxNumberOfRuns = maxNumberOfRuns
        self.maxInputComplexity = maxInputComplexity
        self.mutateDepth = mutateDepth
    }
}

public struct CommandLineFuzzerWorldInfo {
    public var rand: FuzzerPRNG = FuzzerPRNG(seed: arc4random())
    public var inputFile: File? = nil
    public var inputCorpora: [Folder] = []
    public var outputCorpus: Folder? = nil
    public var outputCorpusNames: Set<String> = []
    public var artifactsFolder: Folder? = (try? Folder.current.subfolder(named: "artifacts")) ?? Folder.current
    public var artifactsNameSchema: ArtifactSchema.Name = ArtifactSchema.Name(components: [.kind, .literal("-"), .hash], ext: "json")
    public var artifactsContentSchema: ArtifactSchema.Content = ArtifactSchema.Content(features: false, score: false, hash: false, complexity: false, kind: false)
    public init() {}
}

public struct CommandLineFuzzerWorld <Input, Properties> : FuzzerWorld
    where
    Input: Codable,
    Properties: FuzzerInputProperties,
    Properties.Input == Input
{
    public typealias Feature = CodeCoverageSensor.Feature
    
    public var info: CommandLineFuzzerWorldInfo
    public var rand: FuzzerPRNG {
        get { return info.rand }
        set { info.rand = newValue }
    }
    
    public init(info: CommandLineFuzzerWorldInfo) {
        self.info = info
    }
    
    public func clock() -> UInt {
        return UInt(DispatchTime.now().rawValue / 1_000)
    }
    public func getPeakMemoryUsage() -> UInt {
        var r: rusage = rusage.init()
        if getrusage(RUSAGE_SELF, &r) != 0 {
            return 0
        }
        return UInt(r.ru_maxrss) >> 20
    }
    
    public func saveArtifact(input: Input, features: [Feature]?, score: Double?, kind: ArtifactKind) throws {
        guard let artifactsFolder = info.artifactsFolder else {
            return
        }
        let complexity = Properties.complexity(of: input)
        let hash = Properties.hash(of: input)
        let content = Artifact.Content.init(schema: info.artifactsContentSchema, input: input, features: features, score: score, hash: hash, complexity: complexity, kind: kind)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(content)
        let nameInfo = ArtifactNameInfo(hash: hash, complexity: complexity, kind: kind)
        let name = ArtifactNameWithoutIndex(schema: info.artifactsNameSchema, info: nameInfo).fillGapToBeUnique(from: readArtifactsFolderNames())
        print("Saving \(kind) at \(artifactsFolder.path)\(name)")
        try artifactsFolder.createFileIfNeeded(withName: name, contents: data)
    }
    
    public func readArtifactsFolderNames() -> Set<String> {
        guard let artifactsFolder = info.artifactsFolder else {
            return []
        }
        return Set(artifactsFolder.files.map { $0.name })
    }
    
    public func readInputFile() throws -> Input {
        let decoder = JSONDecoder()
        
        let data = try info.inputFile!.read()
        return try decoder.decode(Artifact<Input>.Content.self, from: data).input
    }
    
    public func readInputCorpus() throws -> [Input] {
        let decoder = JSONDecoder()
        return try info.inputCorpora
            .flatMap { $0.files }
            .map { try decoder.decode(Artifact<Input>.Content.self, from: $0.read()).input }
    }
    
    public func removeFromOutputCorpus(_ input: Input) throws {
        guard let outputCorpus = info.outputCorpus else { return }
        try outputCorpus.file(named: hexString(Properties.hash(of: input))).delete()
    }
    
    public mutating func addToOutputCorpus(_ input: Input) throws {
        guard let outputCorpus = info.outputCorpus else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(input)
        let nameInfo = ArtifactNameInfo(hash: Properties.hash(of: input), complexity: Properties.complexity(of: input), kind: .input)
        let name = ArtifactNameWithoutIndex(schema: info.artifactsNameSchema, info: nameInfo).fillGapToBeUnique(from: [])
        info.outputCorpusNames.insert(name)
        try outputCorpus.createFileIfNeeded(withName: name, contents: data)
    }
    
    public func reportEvent(_ event: FuzzerEvent, stats: FuzzerStats) {
        switch event {
        case .start:
            print("START")
        case .done:
            print("DONE")
        case .new:
            print("NEW\t", terminator: "")
        case .didReadCorpus:
            print("FINISHED READING CORPUS")
        case .caughtSignal(let signal):
            switch signal {
            case .illegalInstruction, .abort, .busError, .floatingPointException:
                print("\n================ CRASH DETECTED ================")
            case .interrupt:
                print("\n================ RUN INTERRUPTED ================")
            default:
                print("\n================ SIGNAL \(signal) ================")
            }
        case .testFailure:
            print("\n================ TEST FAILED ================")
        }
        print("\(stats.totalNumberOfRuns)", terminator: "\t")
        print("score: \(stats.score)", terminator: "\t")
        print("corp: \(stats.poolSize)", terminator: "\t")
        print("exec/s: \(stats.executionsPerSecond)", terminator: "\t")
        print("rss: \(stats.rss)")
    }
}

/**
 Return the hexadecimal representation of the given integer
*/
func hexString(_ h: Int) -> String {
    let bits = UInt64(bitPattern: Int64(h))
    return String(bits, radix: 16, uppercase: false)
}
