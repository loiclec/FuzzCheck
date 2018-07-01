
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
        stats.corpusSize = corpus.numActiveUnits
        stats.totalPCCoverage = TracePC.getTotalEdgeCoverage()
        stats.score = Int(corpus.coverageScore)
        stats.rss = Int(world.getPeakMemoryUsage())
    }
    
    func receive(signal: Signal) -> Never {
        world.reportEvent(.caughtSignal(signal), stats: stats)
        switch signal {
        case .illegalInstruction, .abort, .busError, .floatingPointException:
            TracePC.crashed = true
            var features: [Feature] = []
            TracePC.collectFeatures { features.append($0) }
            try! world.saveArtifact(unit: unit, features: nil, coverage: nil, complexity: unit.complexity(), hash: nil, kind: .crash)
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

enum AnalysisKind: Equatable {
    case readingCorpus
    case loopIteration(mutatingUnitIndex: CorpusIndex)
}

public enum FuzzerStopReason: CustomStringConvertible {
    case crash
    case timeout
    
    public var description: String {
        switch self {
        case .crash: return "crash"
        case .timeout: return "timeout"
        }
    }
}

public enum FuzzerUpdateKind: Equatable, CustomStringConvertible {
    case new
    case reduce
    case start
    case didReadCorpus
    case done
    
    public var description: String {
        switch self {
        case .new:
            return "NEW "
        case .reduce:
            return "REDUCE"
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
        case replace(index: CorpusIndex, features: [Feature], complexity: Double)
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
            try! info.world.saveArtifact(unit: info.unit, features: nil, coverage: nil, complexity: info.unit.complexity(), hash: nil, kind: .testFailure)
            exit(FuzzerTerminationStatus.testFailure.rawValue)
        }
        TracePC.recording = false

        info.stats.totalNumberOfRuns += 1
    }

    func analyze() -> AnalysisResult {
        let currentUnitComplexity = info.unit.complexity()
        
        var uniqueFeatures: [Feature] = []
        var replacingFeatures: [(Feature, CorpusIndex)] = []
        
        var otherFeatures: [Feature] = []
        
        TracePC.collectFeatures { feature in
            guard let (_, oldComplexity, oldCorpusIndex) = info.corpus.allFeatures[feature.reduced] else {
                uniqueFeatures.append(feature)
                return
            }
            if currentUnitComplexity < oldComplexity {
                replacingFeatures.append((feature, oldCorpusIndex))
                return
            } else {
                otherFeatures.append(feature)
                return
            }
        }
        
        // #HGqvcfCLVhGr
        guard !(replacingFeatures.isEmpty && uniqueFeatures.isEmpty) else {
            return .nothing
        }
        
        // because of #HGqvcfCLVhGr I know that replacingFeatures is not empty
        if
            uniqueFeatures.isEmpty,
            case let index = replacingFeatures[0].1,
            replacingFeatures.allSatisfy({ $0.1 == index })
        {
            let oldUnitInfo = info.corpus[index]
            // still have to check that the old unit does not contain features not included in the current unit
            // only if they are completely equal can we replace the old unit by the new one
            // we can compare them in that way because both collections are sorted, see: #mxrvFXBpY9ij
            
            // TODO: why do I compare to the initially unique and replacing-best features instead
            //       of all of them? I *think* because these two types of features represent what
            //       is interesting about the old unit, and we do not care about its other
            //       properties, so it is not a loss if we lose them. But is that true?
            if replacingFeatures.lazy.map({$0.0}) == (oldUnitInfo.initiallyUniqueFeatures + oldUnitInfo.initiallyReplacingBestUnitForFeatures) {
                return .replace(index: index, features: replacingFeatures.map{$0.0}, complexity: currentUnitComplexity)
            } else {
                // else if the old unit had more features than the current unit,
                // then the current unit is not interesting at all and we ignore it
                // TODO: is that true? maybe there is some value in keeping simpler,
                //       less interesting units anyway? Just give them a low score.
                return .nothing
            }
        }
        
        let newUnitInfo = Info.Corpus.UnitInfo(
            unit: info.unit,
            coverageScore: -1, // coverage score is unitialized
            initiallyUniqueFeatures: uniqueFeatures,
            initiallyReplacingBestUnitForFeatures: replacingFeatures.map { $0.0 },
            otherFeatures: otherFeatures
        )
        return .new(newUnitInfo)
    }
    
    func updateCorpusAfterAnalysis(_ result: AnalysisResult) throws {
        switch result {
        case .new(let unitInfo):
            let effect = info.corpus.append(unitInfo)
            try effect(&info.world)

            info.corpus.updateScoresAndWeights()
            
        case .replace(let index, let features, let complexity):
            let effect = info.corpus.replace(index, with: info.unit)
            try effect(&info.world)

            for f in features {
                let reduced = f.reduced
                let currentCount = info.corpus.allFeatures[reduced]!.0
                info.corpus.allFeatures[reduced] = (currentCount, complexity, index)
            }
            info.corpus.updateScoresAndWeights()
            
        case .nothing:
            return
        }
    }
    
    func processNextUnits() throws {
        let idx = info.corpus.chooseUnitIdxToMutate(&info.world.rand)
        guard let unit = info.corpus[idx].unit else {
            fatalError("A previously deleted unit was selected. This should never happen, but any bug in the fuzzer might lead to this situation.")
        }
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
        let newUnitInfo = Info.Corpus.UnitInfo(
            unit: input,
            coverageScore: 1,
            initiallyUniqueFeatures: [],
            initiallyReplacingBestUnitForFeatures: [],
            otherFeatures: []
        )
        info.corpus.favoredUnit = newUnitInfo
        info.corpus.updateScoresAndWeights()
        info.settings.maxUnitComplexity = input.complexity().nextDown
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
            case .replace(_): return .updatedCorpus(.reduce)
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
