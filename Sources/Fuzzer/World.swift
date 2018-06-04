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
    
    mutating func saveArtifact(_ artifact: Unit, because reason: FuzzerStopReason) throws
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
    public var globalTimeout: UInt
    public var iterationTimeout: UInt
    public var maxNumberOfRuns: Int
    public var maxUnitComplexity: Complexity
    public var mutateDepth: Int
    public var shuffleAtStartup: Bool

    
    public init(globalTimeout: UInt = UInt.max, iterationTimeout: UInt = UInt.max, maxNumberOfRuns: Int = Int.max, maxUnitComplexity: Complexity = 256.0, mutateDepth: Int = 3, shuffleAtStartup: Bool = true) {
        self.globalTimeout = globalTimeout
        self.iterationTimeout = iterationTimeout
        self.maxNumberOfRuns = maxNumberOfRuns
        self.maxUnitComplexity = maxUnitComplexity
        self.mutateDepth = mutateDepth
        self.shuffleAtStartup = shuffleAtStartup
    }
}

public struct CommandLineFuzzerWorld <Unit: FuzzUnit> : FuzzerWorld {
    
    public var rand: Rand
    public var inputCorpora: [Folder]
    public var outputCorpus: Folder?
    public var artifactsFolder: Folder
    
    public init(rand: Rand = Rand(seed: arc4random()), inputCorpora: [Folder] = [], outputCorpus: Folder? = nil, artifactsFolder: Folder = Folder.current) {
        self.rand = rand
        self.inputCorpora = inputCorpora
        self.outputCorpus = outputCorpus
        self.artifactsFolder = artifactsFolder
    }
    
    public func clock() -> UInt {
        return UInt(DispatchTime.now().rawValue / 1_000)// Darwin.clock()
    }
    public func getPeakMemoryUsage() -> UInt {
        var r: rusage = rusage.init()
        if getrusage(RUSAGE_SELF, &r) != 0 {
            return 0
        }
        return UInt(r.ru_maxrss) >> 20
    }
    
    public func saveArtifact(_ unit: Unit, because reason: FuzzerStopReason) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(unit)
        try artifactsFolder.createFileIfNeeded(withName: "\(reason.description)-\(hexString(unit.hash()))", contents: data)
    }
    
    public func readInputCorpus() throws -> [Unit] {
        let decoder = JSONDecoder()
        return try inputCorpora
            .flatMap { $0.files }
            .map { try decoder.decode(Unit.self, from: $0.read()) }
    }
    
    public func removeFromOutputCorpus(_ unit: Unit) throws {
        guard let outputCorpus = outputCorpus else { return }
        try outputCorpus.file(named: hexString(unit.hash())).delete()
    }
    
    public func addToOutputCorpus(_ unit: Unit) throws {
        guard let outputCorpus = outputCorpus else { return }
        let encoder = JSONEncoder()
        let data = try encoder.encode(unit)
        try outputCorpus.createFileIfNeeded(withName: hexString(unit.hash()), contents: data)
    }
    
    public func reportEvent(_ event: FuzzerEvent, stats: FuzzerStats) {
        switch event {
        case .updatedCorpus(let updateKind):
            print(updateKind, terminator: "\t")
        case .caughtSignal(let signal):
            switch signal {
            case .illegalInstruction, .abort, .busError, .floatingPointException:
                print("\n================ CRASH DETECTED ================")
            case .fileSizeLimitExceeded:
                print("\n================ FILE SIZE EXCEEDED ================")
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
