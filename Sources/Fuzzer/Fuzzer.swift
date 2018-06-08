
import Darwin
import Foundation

public protocol FuzzTest {
    associatedtype Unit
    associatedtype Mut: Mutators where Mut.Mutated == Unit
    
    var mutators: Mut { get }
    
    static func baseUnit() -> Unit
    func newUnit(_ r: inout Rand) -> Unit
    
    func run(_ u: Unit)
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
    let settings: FuzzerSettings
    
    var processStartTime: UInt = 0
    var world: World
    var state: State = .initial

    init(unit: T, settings: FuzzerSettings, world: World) {
        self.unit = unit
        self.stats = FuzzerStats()
        self.settings = settings
        self.world = world
    }
    
    enum State: Equatable {
        case initial
        case didReadCorpora
        case willMutateAndTestOne
        case willRunTest
        case runningTest(startTime: UInt)
        case didRunTest(timeTaken: UInt)
        case willAnalyzeTestRun(AnalysisKind)
        case didAnalyzeTestRun(didUpdateCorpus: Bool)
        case done
    }
    
    func updateStatsAfterRunAnalysis() {
        let now = world.clock()
        let seconds = Double(now - processStartTime) / 1_000_000
        stats.executionsPerSecond = Int((Double(stats.totalNumberOfRuns) / seconds).rounded())
        stats.totalPCCoverage = TracePC.getTotalPCCoverage()
        stats.score = corpus.coverageScore.s
    }
    
    func updatePeakMemoryUsage() {
        stats.rss = Int(world.getPeakMemoryUsage())
    }
    
    func receive(signal: Signal) -> Never {
        world.reportEvent(.caughtSignal(signal), stats: stats)
        switch signal {
        case .illegalInstruction, .abort, .busError, .floatingPointException:
            try! world.saveArtifact(unit, because: .crash)
            exit(1)
            
        case .fileSizeLimitExceeded:
            exit(1)
            
        case .interrupt:
            exit(0)
            
        default:
            exit(1)
        }
    }
}

public final class Fuzzer <FT: FuzzTest, World: FuzzerWorld> where World.Unit == FT.Unit {
    
    typealias Info = FuzzerInfo<FT.Unit, World>
    
    let info: Info
    
    let fuzzTest: FT
    let signalsHandler: SignalsHandler

    public init(fuzzTest: FT, settings: FuzzerSettings, world: World) {
        print(MemoryLayout<Feature>.size, MemoryLayout<Feature>.stride)
        self.fuzzTest = fuzzTest
        print(TracePC.numPCs())
        self.info = Info(unit: FT.baseUnit(), settings: settings, world: world)
    
        let signals: [Signal] = [.segmentationViolation, .busError, .abort, .illegalInstruction, .floatingPointException, .interrupt, .softwareTermination, .fileSizeLimitExceeded]
        
        self.signalsHandler = SignalsHandler(signals: signals) { [info] signal in
            info.receive(signal: signal)
        }
    }
}

enum AnalysisKind: Equatable {
    case readingCorpus
    case loopIteration(mutatingUnitIndex: CorpusIndex)
    
    var mayDeleteFile: Bool {
        switch self {
        case .readingCorpus:
            return false
        case .loopIteration(_):
            return true
        }
    }
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

public enum FuzzerUpdateKind: CustomStringConvertible {
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
    func runTest() {
        guard case .willRunTest = info.state else { preconditionFailure() }
        
        TracePC.resetMaps()
        
        let startTime = info.world.clock()
        info.state = .runningTest(startTime: startTime)
        
        _ = fuzzTest.run(info.unit)
        
        info.state = .didRunTest(timeTaken: info.world.clock() - startTime)

        info.stats.totalNumberOfRuns += 1
    }
    func analyzeTestRun() {
        guard case .willAnalyzeTestRun(let analysisKind) = info.state else {
            preconditionFailure()
        }
        
        let currentUnitComplexity = info.unit.complexity()
        
        var uniqueFeatures: [Feature] = []
        var replacingFeatures: [(Feature, CorpusIndex)] = []
        
        TracePC.collectFeatures { feature in
            // a feature is Comparable, and they are passed here in growing order. see: #mxrvFXBpY9ij
            if let (oldComplexity, oldCorpusIndex) = info.corpus.unitInfoForFeature[feature] {
                if currentUnitComplexity < oldComplexity {
                    return replacingFeatures.append((feature, oldCorpusIndex))
                } else {
                    return
                }
            } else {
                uniqueFeatures.append(feature)
            }
        }
        
        info.updateStatsAfterRunAnalysis()
        
        // #HGqvcfCLVhGr
        guard !(replacingFeatures.isEmpty && uniqueFeatures.isEmpty) else {
            info.state = .didAnalyzeTestRun(didUpdateCorpus: false) // TODO: double check that
            return
        }
  
        // because of #HGqvcfCLVhGr I know that replacingFeatures is not empty
        if
            uniqueFeatures.isEmpty,
            case let index = replacingFeatures[0].1,
            replacingFeatures.allSatisfy({ $0.1 == index })
        {
            
            let oldUnitInfo = info.corpus.units[index.value]
            // still have to check that the old unit does not contain features not included in the current unit
            // only if they are completely equal can we replace the old unit by the new one
            // we can compare them in that way because both collections are sorted, see: #mxrvFXBpY9ij
            if replacingFeatures.lazy.map({$0.0}) == oldUnitInfo.uniqueFeaturesSet {
                let effect = info.corpus.replace(index, with: info.unit)
                try! effect(&info.world)
                
                for (f, _) in replacingFeatures {
                    info.corpus.unitInfoForFeature[f] = (currentUnitComplexity, index)
                }
                info.state = .didAnalyzeTestRun(didUpdateCorpus: true) // TODO: double check that
                return
            }
            // else if the old unit had more features than the current unit,
            // then the current unit is not interesting at all and we ignore it
        }
        
        let replacedCoverage = replacingFeatures.reduce(0) { $0 + $1.0.coverage.importance.s }
        let newCoverage = uniqueFeatures.reduce(0) { $0 + $1.coverage.importance.s }
        
        let coverageScore = Feature.Coverage.Score(replacedCoverage + newCoverage)
        info.corpus.coverageScore.s += newCoverage
        
        let newUnitInfo = Info.Corpus.UnitInfo(
            unit: info.unit,
            coverageScore: coverageScore,
            mayDeleteFile: analysisKind.mayDeleteFile,
            reduced: false,
            uniqueFeaturesSet: replacingFeatures.map { $0.0 } + uniqueFeatures
        )
        
        for (feature, oldUnitInfoIndex) in replacingFeatures {
            info.corpus.units[oldUnitInfoIndex.value].coverageScore.s -= feature.coverage.importance.s
            precondition(info.corpus.units[oldUnitInfoIndex.value].coverageScore >= 0)
            if info.corpus.units[oldUnitInfoIndex.value].coverageScore == 0 {
                let effect = info.corpus.deleteUnit(oldUnitInfoIndex)
                try! effect(&info.world)
            }
            info.corpus.unitInfoForFeature[feature] = (currentUnitComplexity, CorpusIndex(value: info.corpus.units.endIndex))
        }
        for feature in uniqueFeatures {
            info.corpus.unitInfoForFeature[feature] = (currentUnitComplexity, CorpusIndex(value: info.corpus.units.endIndex))
        }
        
        info.corpus.units.append(newUnitInfo)
        info.corpus.updateCumulativeWeights()
        info.state = .didAnalyzeTestRun(didUpdateCorpus: true)
    }
   
    func mutateAndTestOne() {
        guard case .willMutateAndTestOne = info.state else {
            preconditionFailure()
        }
        let idx = info.corpus.chooseUnitIdxToMutate(&info.world.rand)
        let unit = info.corpus.units[idx.value].unit ?? fuzzTest.newUnit(&info.world.rand) // TODO: is this correct?
        info.unit = unit
        
        for _ in 0 ..< info.settings.mutateDepth {
            guard info.stats.totalNumberOfRuns < info.settings.maxNumberOfRuns else { break }
            guard fuzzTest.mutators.mutate(&info.unit, &info.world.rand) else { break }
            guard info.unit.complexity() < info.settings.maxUnitComplexity else { break }
            info.state = .willRunTest

            runTest()
            
            info.state = .willAnalyzeTestRun(.loopIteration(mutatingUnitIndex: idx))
            analyzeTestRun()

            guard case .didAnalyzeTestRun(let updatedCorpus) = info.state else { preconditionFailure() }
            
            if updatedCorpus {
                info.updatePeakMemoryUsage()
                let updateKind: FuzzerUpdateKind = info.corpus.units[idx.value].reduced ? .reduce : .new
                info.world.reportEvent(.updatedCorpus(updateKind), stats: info.stats)
                try! info.world.addToOutputCorpus(info.unit)
            }
        }
    }

    public func loop() {
        info.processStartTime = info.world.clock()
        info.world.reportEvent(.updatedCorpus(.start), stats: info.stats)
        
        readAndExecuteCorpora()
        info.world.reportEvent(.updatedCorpus(.didReadCorpus), stats: info.stats)
    
        while info.stats.totalNumberOfRuns < info.settings.maxNumberOfRuns {
            info.state = .willMutateAndTestOne
            mutateAndTestOne()
        }
        info.state = .done
        info.world.reportEvent(.updatedCorpus(.done), stats: info.stats)
    }
    
    func readAndExecuteCorpora() {
        var units = [info.unit] + (try! info.world.readInputCorpus())
        
        //let complexities = units.map { $0.complexity() }
        // let totalComplexity = complexities.reduce(0.0 as Complexity) { Complexity($0.value + $1.value) }
        //let maxUnitComplexity = complexities.reduce(0.0) { max($0, $1) }
        // let minUnitComplexity = complexities.reduce(Complexity(Double.greatestFiniteMagnitude)) { min($0, $1) }
        
//        if maxUnitComplexity == 0.0 {
//            self.maxUnitComplexity = defaultMaxUnitComplexity
//        }
        // TODO: print
        
        if info.settings.shuffleAtStartup {
            info.world.rand.shuffle(&units)
        }
        // TODO: prefer small
        
        for u in units {
            // TODO: max complexity
            info.unit = u
            info.state = .willRunTest
            runTest()
            info.state = .willAnalyzeTestRun(.readingCorpus)
            analyzeTestRun()
        }
        
        info.state = .didReadCorpora
    }
}







