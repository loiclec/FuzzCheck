
import Basic
import Darwin
import Foundation

/// The reason why the fuzzer terminated, to be passed as argument to `exit(..)`
public enum FuzzerTerminationStatus: Int32 {
    case success = 0
    case crash = 1
    case testFailure = 2
    case unknown = 3
}

public final class FuzzerState <Unit, Properties, World>
    where
    World: FuzzerWorld,
    World.Unit == Unit,
    Properties: FuzzUnitProperties,
    Properties.Unit == Unit
{
    
    let corpus: Corpus = Corpus()
    var unit: Unit

    var stats: FuzzerStats
    var settings: FuzzerSettings
    
    var processStartTime: UInt = 0
    var world: World

    init(unit: Unit, settings: FuzzerSettings, world: World) {
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
            try! world.saveArtifact(unit: unit, features: features, coverage: corpus.coverageScore, kind: .crash)
            exit(FuzzerTerminationStatus.crash.rawValue)
            
        case .interrupt:
            exit(FuzzerTerminationStatus.success.rawValue)
            
        default:
            exit(FuzzerTerminationStatus.unknown.rawValue)
        }
    }
}

public typealias CommandLineFuzzer <FuzzUnit: FuzzUnit> = Fuzzer<FuzzUnit.Unit, FuzzUnit, FuzzUnit, CommandLineFuzzerWorld<FuzzUnit.Unit, FuzzUnit>> where FuzzUnit.Unit: Codable

public final class Fuzzer <Unit, Generator, Properties, World>
    where
    Generator: FuzzUnitGenerator,
    Properties: FuzzUnitProperties,
    World: FuzzerWorld,
    Generator.Unit == Unit,
    Properties.Unit == Unit,
    World.Unit == Unit
{
    
    typealias State = FuzzerState<Unit, Properties, World>
    
    let state: State
    let generator: Generator
    let test: (Unit) -> Bool
    let signalsHandler: SignalsHandler
    
    public init(test: @escaping (Unit) -> Bool, generator: Generator, settings: FuzzerSettings, world: World) {
        self.generator = generator
        self.test = test
        self.state = State(unit: generator.baseUnit, settings: settings, world: world)
    
        let signals: [Signal] = [.segmentationViolation, .busError, .abort, .illegalInstruction, .floatingPointException, .interrupt, .softwareTermination, .fileSizeLimitExceeded]
        
        self.signalsHandler = SignalsHandler(signals: signals) { [state] signal in
            state.receive(signal: signal)
        }
        
        precondition(Foundation.Thread.isMainThread, "Fuzzer can only be initialized on the main thread")
        
        let idx = Foundation.Thread.callStackSymbols.firstIndex(where: { $0.contains(" main + ")})!
        let adr = Foundation.Thread.callStackReturnAddresses[idx].uintValue
        NormalizedPC.constant = adr
    }
}

extension Fuzzer where Unit: Codable, Properties == Generator, World == CommandLineFuzzerWorld<Generator.Unit, Generator> {
    
    public static func launch(test: @escaping (Unit) -> Bool, generator: Generator) throws {
        
        let (parser, settingsBinder, worldBinder, _) = CommandLineFuzzerWorldInfo.argumentsParser()
        do {
            let res = try parser.parse(Array(CommandLine.arguments.dropFirst()))
            var settings: FuzzerSettings = FuzzerSettings()
            try settingsBinder.fill(parseResult: res, into: &settings)
            var world: CommandLineFuzzerWorldInfo = CommandLineFuzzerWorldInfo()
            try worldBinder.fill(parseResult: res, into: &world)

            let fuzzer = Fuzzer(test: test, generator: generator, settings: settings, world: CommandLineFuzzerWorld(info: world))
            switch fuzzer.state.settings.command {
            case .fuzz:
                try fuzzer.loop()
            case .minimize:
                try fuzzer.minimizeLoop()
            case .read:
                fuzzer.state.unit = try fuzzer.state.world.readInputFile()
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
        case new(State.Corpus.UnitInfo)
        case nothing
    }

    func testCurrentUnit() {
        TracePC.resetTestRecordings()

        TracePC.recording = true
        let success = test(state.unit)
        TracePC.recording = false

        guard success else {
            state.world.reportEvent(.testFailure, stats: state.stats)
            var features: [Feature] = []
            TracePC.collectFeatures { features.append($0) }
            try! state.world.saveArtifact(unit: state.unit, features: features, coverage: state.corpus.coverageScore, kind: .testFailure)
            exit(FuzzerTerminationStatus.testFailure.rawValue)
        }
        TracePC.recording = false

        state.stats.totalNumberOfRuns += 1
    }

    func analyze() -> AnalysisResult {
        let currentUnitComplexity = Properties.complexity(of: state.unit)
        
        var bestUnitForFeatures: [Feature] = []
        
        var otherFeatures: [Feature] = []
        
        TracePC.collectFeatures { feature in
            guard let oldComplexity = state.corpus.smallestUnitComplexityForFeature[feature.reduced] else {
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
        let newUnitInfo = State.Corpus.UnitInfo(
            unit: state.unit,
            complexity: currentUnitComplexity,
            features: bestUnitForFeatures + otherFeatures
        )
        return .new(newUnitInfo)
    }
    
    func updateCorpusAfterAnalysis(_ result: AnalysisResult) throws {
        switch result {
        case .new(let unitInfo):
            let effect = state.corpus.append(unitInfo)
            try effect(&state.world)
            state.corpus.updateScoresAndWeights()

        case .nothing:
            return
        }
    }
    
    func processNextUnits() throws {
        let idx = state.corpus.chooseUnitIdxToMutate(&state.world.rand)
        let unit = state.corpus[idx].unit
        state.unit = unit
        for _ in 0 ..< state.settings.mutateDepth {
            guard state.stats.totalNumberOfRuns < state.settings.maxNumberOfRuns else { break }
            guard generator.mutate(&state.unit, &state.world.rand) else { break  }
            guard Properties.complexity(of: state.unit) < state.settings.maxUnitComplexity else { continue }
            try processCurrentUnit()
        }
    }

    public func loop() throws {
        state.processStartTime = state.world.clock()
        state.world.reportEvent(.updatedCorpus(.start), stats: state.stats)
        
        try processInitialUnits()
        state.world.reportEvent(.updatedCorpus(.didReadCorpus), stats: state.stats)
            
        while state.stats.totalNumberOfRuns < state.settings.maxNumberOfRuns {
            try processNextUnits()
        }
        state.world.reportEvent(.updatedCorpus(.done), stats: state.stats)
    }
    
    public func minimizeLoop() throws {
        state.processStartTime = state.world.clock()
        state.world.reportEvent(.updatedCorpus(.start), stats: state.stats)
        let input = try state.world.readInputFile()
        let favoredUnit = State.Corpus.UnitInfo(
            unit: input,
            complexity: Properties.complexity(of: input),
            features: []
        )
        state.corpus.favoredUnit = favoredUnit
        state.corpus.updateScoresAndWeights()
        state.settings.maxUnitComplexity = favoredUnit.complexity.nextDown
        state.world.reportEvent(.updatedCorpus(.didReadCorpus), stats: state.stats)
        while state.stats.totalNumberOfRuns < state.settings.maxNumberOfRuns {
            try processNextUnits()
        }
        state.world.reportEvent(.updatedCorpus(.done), stats: state.stats)
    }
    
    func processCurrentUnit() throws {
        testCurrentUnit()
        
        let res = analyze()
        try updateCorpusAfterAnalysis(res)
        state.updateStats()
        guard let event: FuzzerEvent = {
            switch res {
            case .new(_)    : return .updatedCorpus(.new)
            case .nothing   : return nil
            }
        }() else {
            return
        }
        state.world.reportEvent(event, stats: state.stats)
    }
    
    func processInitialUnits() throws {
        var units = try state.world.readInputCorpus()
        if units.isEmpty {
            units += generator.initialUnits(&state.world.rand)
        }
        // Filter the units that are too complex
        units = units.filter { Properties.complexity(of: $0) <= state.settings.maxUnitComplexity }
        
        for u in units {
            state.unit = u
            try processCurrentUnit()
        }
    }
}
