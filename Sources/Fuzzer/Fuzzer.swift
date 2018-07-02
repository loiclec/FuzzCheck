
import Basic
import Darwin
import Foundation

public enum FuzzerTerminationStatus: Int32 {
    case success = 0
    case crash = 1
    case testFailure = 2
    case unknown = 3
}
/*
 For some reason having the fuzzer be generic over FuzzTest and containing the SignalsHandler was a problem.
 So I created another type that only depends on the FuzzUnit type and gather as much data as I can here, leaving
 the fuzzer with only FuzzTest-related properties and methods.
 */
public final class FuzzerInfo <T, World: FuzzerWorld> where World.Unit == T {
    
    let corpus: Corpus = Corpus()
    var unit: T

    var stats: FuzzerStats
    var settings: FuzzerSettings
    
    var processStartTime: UInt = 0
    var world: World

    init(unit: T, settings: FuzzerSettings, world: World) {
        self.unit = unit
        self.stats = FuzzerStats()
        self.settings = settings
        self.world = world
    }

    func updateStats() {
        let now = world.clock()
        let seconds = Double(now - processStartTime) / 1_000_000
        stats.executionsPerSecond = Int((Double(stats.totalNumberOfRuns) / seconds).rounded())
        stats.corpusSize = corpus.units.count
        stats.totalPCCoverage = TracePC.getTotalEdgeCoverage()
        stats.score = corpus.coverageScore.rounded()
        stats.rss = Int(world.getPeakMemoryUsage())
    }
    
    func receive(signal: Signal) -> Never {
        world.reportEvent(.caughtSignal(signal), stats: stats)
        switch signal {
        case .illegalInstruction, .abort, .busError, .floatingPointException:
            TracePC.crashed = true
            var features: [Feature] = []
            TracePC.collectFeatures { features.append($0) }
            try! world.saveArtifact(unit: unit, features: nil, coverage: nil, hash: nil, kind: .crash)
            exit(FuzzerTerminationStatus.crash.rawValue)
            
        case .interrupt:
            exit(FuzzerTerminationStatus.success.rawValue)
            
        default:
            exit(FuzzerTerminationStatus.unknown.rawValue)
        }
    }
}

public typealias CommandLineFuzzer <UnitGen: FuzzUnitGenerator> = Fuzzer<UnitGen, CommandLineFuzzerWorld<UnitGen.Unit>>

public final class Fuzzer <UnitGen: FuzzUnitGenerator, World: FuzzerWorld> where World.Unit == UnitGen.Unit {
    
    typealias Info = FuzzerInfo<UnitGen.Unit, World>
    
    let info: Info
    let generator: UnitGen
    let test: (UnitGen.Unit) -> Bool
    let signalsHandler: SignalsHandler
    
    public init(test: @escaping (UnitGen.Unit) -> Bool, generator: UnitGen, settings: FuzzerSettings, world: World) {
        self.generator = generator
        self.test = test
        self.info = Info(unit: generator.baseUnit, settings: settings, world: world)
    
        let signals: [Signal] = [.segmentationViolation, .busError, .abort, .illegalInstruction, .floatingPointException, .interrupt, .softwareTermination, .fileSizeLimitExceeded]
        
        self.signalsHandler = SignalsHandler(signals: signals) { [info] signal in
            info.receive(signal: signal)
        }
        
        precondition(Foundation.Thread.isMainThread, "Fuzzer can only be initialized on the main thread")
        
        let idx = Foundation.Thread.callStackSymbols.firstIndex(where: { $0.contains(" main + ")})!
        let adr = Foundation.Thread.callStackReturnAddresses[idx].uintValue
        NormalizedPC.constant = adr
    }
}

extension Fuzzer where World == CommandLineFuzzerWorld<UnitGen.Unit> {
    public static func launch(test: @escaping (UnitGen.Unit) -> Bool, generator: UnitGen) throws {
        
        let (parser, settingsBinder, worldBinder, _) = CommandLineFuzzerWorldInfo.argumentsParser()
        do {
            let res = try parser.parse(Array(CommandLine.arguments.dropFirst()))
            var settings: FuzzerSettings = FuzzerSettings()
            try settingsBinder.fill(parseResult: res, into: &settings)
            var world: CommandLineFuzzerWorldInfo = CommandLineFuzzerWorldInfo()
            try worldBinder.fill(parseResult: res, into: &world)

            let fuzzer = Fuzzer(test: test, generator: generator, settings: settings, world: CommandLineFuzzerWorld(info: world))
            switch fuzzer.info.settings.command {
            case .fuzz:
                try fuzzer.loop()
            case .minimize:
                try fuzzer.minimizeLoop()
            case .read:
                fuzzer.info.unit = try fuzzer.info.world.readInputFile()
                fuzzer.testCurrentUnit()
            }
        } catch let e {
            print(e)
            parser.printUsage(on: stdoutStream)
        }
    }
}

public enum FuzzerUpdateKind: Equatable, CustomStringConvertible {
    case new
    case start
    case didReadCorpus
    case done
    
    public var description: String {
        switch self {
        case .new:
            return "NEW "
        case .start:
            return "START"
        case .didReadCorpus:
            return "DID READ CORPUS"
        case .done:
            return "DONE"
        }
    }
}

extension Fuzzer {
    enum AnalysisResult {
        case new(Info.Corpus.UnitInfo)
        case nothing
    }

    func testCurrentUnit() {
        TracePC.resetTestRecordings()

        TracePC.recording = true
        let success = test(info.unit)
        TracePC.recording = false

        guard success else {
            info.world.reportEvent(.testFailure, stats: info.stats)
            var features: [Feature] = []
            TracePC.collectFeatures { features.append($0) }
            try! info.world.saveArtifact(unit: info.unit, features: nil, coverage: nil, hash: nil, kind: .testFailure)
            exit(FuzzerTerminationStatus.testFailure.rawValue)
        }
        TracePC.recording = false

        info.stats.totalNumberOfRuns += 1
    }

    func analyze() -> AnalysisResult {
        let currentUnitComplexity = info.unit.complexity()
        
        var bestUnitForFeatures: [Feature] = []
        
        var otherFeatures: [Feature] = []
        
        TracePC.collectFeatures { feature in
            guard let oldComplexity = info.corpus.smallestUnitComplexityForFeature[feature.reduced] else {
                bestUnitForFeatures.append(feature)
                return
            }
            if currentUnitComplexity < oldComplexity {
                bestUnitForFeatures.append(feature)
                return
            } else {
                otherFeatures.append(feature)
                return
            }
        }
        
        // #HGqvcfCLVhGr
        guard !bestUnitForFeatures.isEmpty else {
            return .nothing
        }
        let newUnitInfo = Info.Corpus.UnitInfo(
            unit: info.unit,
            complexity: currentUnitComplexity,
            features: bestUnitForFeatures + otherFeatures
        )
        return .new(newUnitInfo)
    }
    
    func updateCorpusAfterAnalysis(_ result: AnalysisResult) throws {
        switch result {
        case .new(let unitInfo):
            let effect = info.corpus.append(unitInfo)
            try effect(&info.world)
            info.corpus.updateScoresAndWeights()

        case .nothing:
            return
        }
    }
    
    func processNextUnits() throws {
        let idx = info.corpus.chooseUnitIdxToMutate(&info.world.rand)
        let unit = info.corpus[idx].unit
        info.unit = unit
        for _ in 0 ..< info.settings.mutateDepth {
            guard info.stats.totalNumberOfRuns < info.settings.maxNumberOfRuns else { break }
            guard generator.mutators.mutate(&info.unit, &info.world.rand) else { break  }
            guard info.unit.complexity() < info.settings.maxUnitComplexity else { continue }
            try processCurrentUnit()
        }
    }

    public func loop() throws {
        info.processStartTime = info.world.clock()
        info.world.reportEvent(.updatedCorpus(.start), stats: info.stats)
        
        try processInitialUnits()
        info.world.reportEvent(.updatedCorpus(.didReadCorpus), stats: info.stats)
            
        while info.stats.totalNumberOfRuns < info.settings.maxNumberOfRuns {
            try processNextUnits()
        }
        info.world.reportEvent(.updatedCorpus(.done), stats: info.stats)
    }
    
    public func minimizeLoop() throws {
        info.processStartTime = info.world.clock()
        info.world.reportEvent(.updatedCorpus(.start), stats: info.stats)
        let input = try info.world.readInputFile()
        let favoredUnit = Info.Corpus.UnitInfo(
            unit: input,
            complexity: input.complexity(),
            features: []
        )
        info.corpus.favoredUnit = favoredUnit
        info.corpus.updateScoresAndWeights()
        info.settings.maxUnitComplexity = favoredUnit.complexity.nextDown
        info.world.reportEvent(.updatedCorpus(.didReadCorpus), stats: info.stats)
        while info.stats.totalNumberOfRuns < info.settings.maxNumberOfRuns {
            try processNextUnits()
        }
        info.world.reportEvent(.updatedCorpus(.done), stats: info.stats)
    }
    
    func processCurrentUnit() throws {
        testCurrentUnit()
        
        let res = analyze()
        try updateCorpusAfterAnalysis(res)
        info.updateStats()
        guard let event: FuzzerEvent = {
            switch res {
            case .new(_)    : return .updatedCorpus(.new)
            case .nothing   : return nil
            }
        }() else {
            return
        }
        info.world.reportEvent(event, stats: info.stats)
    }
    
    func processInitialUnits() throws {
        var units = try info.world.readInputCorpus()
        if units.isEmpty {
            units += generator.initialUnits(&info.world.rand)
        }
        // Filter the units that are too complex
        units = units.filter { $0.complexity() <= info.settings.maxUnitComplexity }
        
        for u in units {
            info.unit = u
            try processCurrentUnit()
        }
    }
}
