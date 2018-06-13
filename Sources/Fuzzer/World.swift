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
    
    mutating func saveArtifact(unit: Unit, features: [Feature]?, coverage: Feature.Coverage.Score?, complexity: Complexity?, hash: Int?, kind: ArtifactKind) throws
    mutating func addToOutputCorpus(_ unit: Unit) throws
    mutating func removeFromOutputCorpus(_ unit: Unit) throws
    mutating func reportEvent(_ event: FuzzerEvent, stats: FuzzerStats)
    
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
    
    public var iterationTimeout: UInt
    public var maxNumberOfRuns: Int
    public var maxUnitComplexity: Complexity
    public var mutateDepth: Int
    public var shuffleAtStartup: Bool
    public var minimize: Bool
    
    public init(iterationTimeout: UInt = UInt.max, maxNumberOfRuns: Int = Int.max, maxUnitComplexity: Complexity = 256.0, mutateDepth: Int = 3, shuffleAtStartup: Bool = true, minimize: Bool = false) {
        self.iterationTimeout = iterationTimeout
        self.maxNumberOfRuns = maxNumberOfRuns
        self.maxUnitComplexity = maxUnitComplexity
        self.mutateDepth = mutateDepth
        self.shuffleAtStartup = shuffleAtStartup
        self.minimize = minimize
    }
}

public struct CommandLineFuzzerWorldInfo {
    public var rand: Rand = Rand(seed: arc4random())
    public var inputCorpora: [Folder] = []
    public var outputCorpus: Folder? = nil
    public var outputCorpusNames: Set<String> = []
    public var artifactsFolder: Folder = Folder.current
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
    
    public func saveArtifact(unit: Unit, features: [Feature]?, coverage: Feature.Coverage.Score?, complexity: Complexity?, hash: Int?, kind: ArtifactKind) throws {
        let content = Artifact.Content.init(schema: info.artifactsContentSchema, unit: unit, features: features, coverage: coverage, hash: hash, complexity: complexity, kind: kind)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(content)
        let nameInfo = ArtifactNameInfo(hash: unit.hash(), complexity: unit.complexity(), kind: kind)
        let name = ArtifactNameWithoutIndex(schema: info.artifactsNameSchema, info: nameInfo).fillGapToBeUnique(from: readArtifactsFolderNames())
        try info.artifactsFolder.createFileIfNeeded(withName: name, contents: data)
    }
    
    public func readArtifactsFolderNames() -> Set<String> {
        return Set(info.artifactsFolder.files.map { $0.name })
    }
    
    public func readInputCorpus() throws -> [Unit] {
        let decoder = JSONDecoder()
        return try info.inputCorpora
            .flatMap { $0.files }
            .map { try decoder.decode(Unit.self, from: $0.read()) }
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
