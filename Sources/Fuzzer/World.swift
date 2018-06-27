//
//  World.swift
//  Fuzzer
//
//  Created by Loïc Lecrenier on 03/06/2018.
//

import Files
import Foundation

public enum FuzzerEvent {
    case updatedCorpus(FuzzerUpdateKind)
    case caughtSignal(Signal)
}

public protocol FuzzerWorld {
    associatedtype Unit: FuzzUnit
    
    mutating func getPeakMemoryUsage() -> UInt
    mutating func clock() -> UInt
    mutating func readInputCorpus() throws -> [Unit]
    mutating func readInputFile() throws -> Unit
    
    mutating func saveArtifact(unit: Unit, features: [Feature]?, coverage: Double?, complexity: Double?, hash: Int?, kind: ArtifactKind) throws
    mutating func addToOutputCorpus(_ unit: Unit) throws
    mutating func removeFromOutputCorpus(_ unit: Unit) throws
    mutating func reportEvent(_ event: FuzzerEvent, stats: FuzzerStats)
    
    mutating func readInputCorpusWithFeatures() throws -> [(Unit, [Feature])]
    
    var rand: Rand { get set }
}

public struct FuzzerStats {
    public var totalNumberOfRuns: Int = 0
    public var totalPCCoverage: Int = 0
    public var score: Int = 0
    public var corpusSize: Int = 0
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
    public var iterationTimeout: UInt
    public var maxNumberOfRuns: Int
    public var maxUnitComplexity: Double
    public var mutateDepth: Int
    public var shuffleAtStartup: Bool
    
    public init(command: Command = .fuzz, iterationTimeout: UInt = UInt.max, maxNumberOfRuns: Int = Int.max, maxUnitComplexity: Double = 256.0, mutateDepth: Int = 3, shuffleAtStartup: Bool = true) {
        self.command = command
        self.iterationTimeout = iterationTimeout
        self.maxNumberOfRuns = maxNumberOfRuns
        self.maxUnitComplexity = maxUnitComplexity
        self.mutateDepth = mutateDepth
        self.shuffleAtStartup = shuffleAtStartup
    }
}

public struct CommandLineFuzzerWorldInfo {
    public var rand: Rand = Rand(seed: arc4random())
    public var inputFile: File? = nil
    public var inputCorpora: [Folder] = []
    public var outputCorpus: Folder? = nil
    public var outputCorpusNames: Set<String> = []
    public var artifactsFolder: Folder? = Folder.current
    public var artifactsNameSchema: ArtifactSchema.Name = ArtifactSchema.Name(atoms: [.hash], ext: nil)
    public var artifactsContentSchema: ArtifactSchema.Content = ArtifactSchema.Content(features: true, coverageScore: true, hash: false, complexity: false, kind: false)
    public init() {}
}

public struct CommandLineFuzzerWorld <Unit: FuzzUnit> : FuzzerWorld {

    public var info: CommandLineFuzzerWorldInfo
    public var rand: Rand {
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
    
    public func saveArtifact(unit: Unit, features: [Feature]?, coverage: Double?, complexity: Double?, hash: Int?, kind: ArtifactKind) throws {
        guard let artifactsFolder = info.artifactsFolder else {
            return
        }
        let content = Artifact.Content.init(schema: info.artifactsContentSchema, unit: unit, features: features, coverage: coverage, hash: hash, complexity: complexity, kind: kind)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(content)
        let nameInfo = ArtifactNameInfo(hash: unit.hash(), complexity: unit.complexity(), kind: kind)
        let name = ArtifactNameWithoutIndex(schema: info.artifactsNameSchema, info: nameInfo).fillGapToBeUnique(from: readArtifactsFolderNames())
        print("Saving crash at \(artifactsFolder.path)\(name)")
        try artifactsFolder.createFileIfNeeded(withName: name, contents: data)
    }
    
    public func readArtifactsFolderNames() -> Set<String> {
        guard let artifactsFolder = info.artifactsFolder else {
            return []
        }
        return Set(artifactsFolder.files.map { $0.name })
    }
    
    public func readInputFile() throws -> Unit {
        let decoder = JSONDecoder()
        
        let data = try info.inputFile!.read()
        return try decoder.decode(Artifact<Unit>.Content.self, from: data).unit
    }
    
    public func readInputCorpus() throws -> [Unit] {
        let decoder = JSONDecoder()
        return try info.inputCorpora
            .flatMap { $0.files }
            .map { try decoder.decode(Artifact<Unit>.Content.self, from: $0.read()).unit }
    }
    
    public mutating func readInputCorpusWithFeatures() throws -> [(Unit, [Feature])] {
        let decoder = JSONDecoder()

        let artifacts = info.inputCorpora
            .flatMap { $0.files }
            .map { file -> Artifact<Unit>.Content in
                do {
                    return try decoder.decode(Artifact<Unit>.Content.self, from: file.read())
                } catch let e {
                    print(e)
                    sleep(4)
                    fatalError()
                }
            }
        return artifacts.map { c in
            (c.unit, c.features!)
        }
    }
    
    public func removeFromOutputCorpus(_ unit: Unit) throws {
        guard let outputCorpus = info.outputCorpus else { return }
        try outputCorpus.file(named: hexString(unit.hash())).delete()
    }
    
    public mutating func addToOutputCorpus(_ unit: Unit) throws {
        guard let outputCorpus = info.outputCorpus else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(unit)
        let nameInfo = ArtifactNameInfo(hash: unit.hash(), complexity: unit.complexity(), kind: .unit)
        let name = ArtifactNameWithoutIndex(schema: info.artifactsNameSchema, info: nameInfo).fillGapToBeUnique(from: [])
        info.outputCorpusNames.insert(name)
        try outputCorpus.createFileIfNeeded(withName: name, contents: data)
    }
    
    public func reportEvent(_ event: FuzzerEvent, stats: FuzzerStats) {
        switch event {
        case .updatedCorpus(let updateKind):
            print(updateKind, terminator: "\t")
        case .caughtSignal(let signal):
            switch signal {
            case .illegalInstruction, .abort, .busError, .floatingPointException:
                print("\n================ CRASH DETECTED ================")
            case .interrupt:
                print("\n================ RUN INTERRUPTED ================")
            default:
                print("\n================ SIGNAL \(signal) ================")
            }
        }
        print("\(stats.totalNumberOfRuns)", terminator: "\t")
        print("cov: \(stats.totalPCCoverage)", terminator: "\t")
        print("score: \(stats.score)", terminator: "\t")
        print("corp: \(stats.corpusSize)", terminator: "\t")
        print("exec/s: \(stats.executionsPerSecond)", terminator: "\t")
        print("rss: \(stats.rss)")
    }
}
