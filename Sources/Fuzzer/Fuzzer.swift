
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
    var settings: FuzzerSettings
    
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
        case willAnalyzeTestRun
        case didAnalyzeTestRun(didUpdateCorpus: FuzzerUpdateKind?)
        case done
    }
    
    func updateStatsAfterRunAnalysis() {
        guard case .didAnalyzeTestRun(_) = state else { fatalError("state should be didAnalyzeTestRun") }
        let now = world.clock()
        let seconds = Double(now - processStartTime) / 1_000_000
        stats.executionsPerSecond = Int((Double(stats.totalNumberOfRuns) / seconds).rounded())
        stats.corpusSize = corpus.numActiveUnits
        stats.totalPCCoverage = TracePC.getTotalPCCoverage()
        stats.score = Int(corpus.coverageScore)
    }
    
    func updatePeakMemoryUsage() {
        stats.rss = Int(world.getPeakMemoryUsage())
    }
    
    func receive(signal: Signal) -> Never {
        world.reportEvent(.caughtSignal(signal), stats: stats)
        switch signal {
        case .illegalInstruction, .abort, .busError, .floatingPointException:
            TracePC.crashed = true
            var features: [Feature] = []
            TracePC.collectFeatures(debug: true) { features.append($0) }
            try! world.saveArtifact(unit: unit, features: features, coverage: nil, complexity: nil, hash: nil, kind: .crash)
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
        self.fuzzTest = fuzzTest
        self.info = Info(unit: FT.baseUnit(), settings: settings, world: world)
    
        let signals: [Signal] = [.segmentationViolation, .busError, .abort, .illegalInstruction, .floatingPointException, .interrupt, .softwareTermination, .fileSizeLimitExceeded]
        
        self.signalsHandler = SignalsHandler(signals: signals) { [info] signal in
            info.receive(signal: signal)
        }
        
        precondition(Foundation.Thread.isMainThread, "Fuzzer can only be initialized on the main thread")
        
        Foundation.Thread.callStackSymbols.forEach { print($0) }
        let idx = Foundation.Thread.callStackSymbols.firstIndex(where: { $0.contains(" main + ")})!
        let adr = Foundation.Thread.callStackReturnAddresses[idx].uintValue
        NormalizedPC.constant = adr
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
    case replace(Int)
    case reduce
    case start
    case didReadCorpus
    case done
    
    public var description: String {
        switch self {
        case .new:
            return "NEW "
        case .replace(let count):
            return "REPLA \(count)"
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
        case replace(index: CorpusIndex, features: [Feature], complexity: Complexity)
        case nothing
    }

    func runTest() {
        guard case .willRunTest = info.state else { fatalError("state should be willRunTest") }
        
        TracePC.resetMaps()
        
        let startTime = info.world.clock()
        info.state = .runningTest(startTime: startTime)
        TracePC.recording = true
        _ = fuzzTest.run(info.unit)
        TracePC.recording = false
        info.state = .didRunTest(timeTaken: info.world.clock() - startTime)

        info.stats.totalNumberOfRuns += 1
    }

    func analyzeTestRun2() -> AnalysisResult {
        guard case .willAnalyzeTestRun = info.state else {
            fatalError("state should be willAnalyzeTestRun")
        }
        
        let currentUnitComplexity = info.unit.complexity()
        
        var uniqueFeatures: [Feature] = []
        var replacingFeatures: [(Feature, CorpusIndex)] = []
        
        var otherFeatures: [Feature] = []
        
        TracePC.collectFeatures(debug: false) { feature in
            // don't collect non-deterministic features
            guard !info.corpus.forbiddenPCGroups.contains(feature.pcGroup) else {
                return
            }
            guard let (_, oldComplexity, oldCorpusIndex) = info.corpus.allFeatures[feature] else {
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
            info.state = .didAnalyzeTestRun(didUpdateCorpus: nil)
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
                info.state = .didAnalyzeTestRun(didUpdateCorpus: .reduce)
                return .replace(index: index, features: replacingFeatures.map{$0.0}, complexity: currentUnitComplexity)
            } else {
                // else if the old unit had more features than the current unit,
                // then the current unit is not interesting at all and we ignore it
                // TODO: is that true? maybe there is some value in keeping simpler,
                //       less interesting units anyway? Just give them a low score.
                info.state = .didAnalyzeTestRun(didUpdateCorpus: nil)
                return .nothing
            }
        }
        
        let newUnitInfo = Info.Corpus.UnitInfo(
            unit: info.unit,
            coverageScore: -1,
            initiallyUniqueFeatures: uniqueFeatures,
            initiallyReplacingBestUnitForFeatures: replacingFeatures.map { $0.0 },
            otherFeatures: otherFeatures
        )
        info.state = .didAnalyzeTestRun(didUpdateCorpus: .new)
        return .new(newUnitInfo)
    }
    
    func analyzeTestRun() {
        /*
        guard case .willAnalyzeTestRun(_) = info.state else {
            preconditionFailure()
        }
        
        let currentUnitComplexity = info.unit.complexity()
        
        var uniqueFeatures: [Feature] = []
        var replacingFeatures: [(Feature, CorpusIndex)] = []
        
        var otherFeatures: [Feature] = []
        
        TracePC.collectFeatures(debug: false) { feature in
            // don't collect non-deterministic features
            if case .valueProfile(let x) = feature, info.corpus.forbiddenValueProfilePCs.contains(x.pc) {
                return
            }
            guard let (_, oldComplexity, oldCorpusIndex) = info.corpus.allFeatures[feature] else {
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
            info.state = .didAnalyzeTestRun(didUpdateCorpus: nil)
            return
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
                let effect = info.corpus.replace(index, with: info.unit)
                try! effect(&info.world)
                
                for (f, _) in replacingFeatures {
                    let currentCount = info.corpus.allFeatures[f]!.0
                    info.corpus.allFeatures[f] = (currentCount, currentUnitComplexity, index)
                }
                info.corpus.updateScoresAndWeights()
                info.state = .didAnalyzeTestRun(didUpdateCorpus: .reduce)
                return
            } else {
                // else if the old unit had more features than the current unit,
                // then the current unit is not interesting at all and we ignore it
                // TODO: is that true? maybe there is some value in keeping simpler,
                //       less interesting units anyway? Just give them a low score.
                info.state = .didAnalyzeTestRun(didUpdateCorpus: nil)
                return
            }
        }
        
        let newUnitInfo = Info.Corpus.UnitInfo(
            unit: info.unit,
            coverageScore: -1,
            initiallyUniqueFeatures: uniqueFeatures,
            initiallyReplacingBestUnitForFeatures: replacingFeatures.map { $0.0 },
            otherFeatures: otherFeatures
        )
        info.corpus.append(newUnitInfo)
        info.corpus.updateScoresAndWeights()
        info.state = .didAnalyzeTestRun(didUpdateCorpus: .new)
        */
    }
   
    func updateCorpusAfterAnalysis(result: AnalysisResult) {
        switch result {
        case .new(let unitInfo):
            info.corpus.append(unitInfo)
            info.corpus.updateScoresAndWeights()
        case .replace(let index, let features, let complexity):
            let effect = info.corpus.replace(index, with: info.unit)
            try! effect(&info.world)
            
            for f in features {
                let currentCount = info.corpus.allFeatures[f]!.0
                info.corpus.allFeatures[f] = (currentCount, complexity, index)
            }
            info.corpus.updateScoresAndWeights()
        case .nothing:
            return
        }
    }
    
    func mutateAndTestOne() {
        guard case .willMutateAndTestOne = info.state else {
            fatalError("state should be willMutateAndTestOne")
        }
        let idx = info.corpus.chooseUnitIdxToMutate(&info.world.rand)
        guard let unit = info.corpus[idx].unit else {
            print(info.corpus.units.map { ($0.coverageScore, $0.unit != nil) })
            print(info.corpus.cumulativeWeights)
            print(idx)
            sleep(10)
            fatalError("This should never happen, but any bug in the fuzzer might lead to this situation.")
        }
        info.unit = unit
        for _ in 0 ..< info.settings.mutateDepth {
            guard info.stats.totalNumberOfRuns < info.settings.maxNumberOfRuns else { break }
            guard fuzzTest.mutators.mutate(&info.unit, &info.world.rand) else { break }
            guard info.unit.complexity() < info.settings.maxUnitComplexity else { break }
            analyze()
            guard case .didAnalyzeTestRun(let updatedCorpus) = info.state else {
                fatalError("state should be didAnalyzeTestRun")
            }
            
            if let updateKind = updatedCorpus {
                info.updatePeakMemoryUsage()
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
    
    public func pickUnitFromInputCorpus() throws -> (FT.Unit, [Feature]) {
        let units = try info.world.readInputCorpusWithFeatures()// readInputCorpus()
        guard !units.isEmpty else {
            fatalError("units should not be empty")
        }
    
        var complexities = units.map { ($0, $0.0.complexity()) }
        complexities.sort { $0.1 > $1.1 }
        let weights = (0 ..< complexities.count).scan(UInt64(1)) { $0 + UInt64($1) }
        // e.g.
        // complexities: [10, 8, 7, 4,  3,  1]
        // weights     : [ 1, 2, 4, 7, 11, 16]
        // so, heavy (quadratic) bias towards less complex units
        let pick = info.world.rand.weightedPickIndex(cumulativeWeights: weights)
        return units[pick]
    }
    
    public func minimizeLoop() {
        info.processStartTime = info.world.clock()
        info.world.reportEvent(.updatedCorpus(.start), stats: info.stats)
        
        let (input, features) = try! pickUnitFromInputCorpus()
        let newUnitInfo = Info.Corpus.UnitInfo(
            unit: input,
            coverageScore: -1,
            initiallyUniqueFeatures: features,
            initiallyReplacingBestUnitForFeatures: [],
            otherFeatures: []
        )
        info.corpus.append(newUnitInfo)
        info.corpus.updateScoresAndWeights()
        
        info.settings.maxUnitComplexity = .init(input.complexity().value.nextDown)
        info.world.reportEvent(.updatedCorpus(.didReadCorpus), stats: info.stats)
        while info.stats.totalNumberOfRuns < info.settings.maxNumberOfRuns {
            info.state = .willMutateAndTestOne
            mutateAndTestOne()
        }
        info.state = .done
        info.world.reportEvent(.updatedCorpus(.done), stats: info.stats)
    }
    
    func analyze() {
        var previousUniquePCGroups: Set<PC> = []
        var i = 0
        var tryAgain = false
        var res:  AnalysisResult = .nothing
        Loop: while tryAgain || i < 100 {
            defer { i += 1 }
            info.state = .willRunTest
            runTest()
            
            info.state = .willAnalyzeTestRun
            // analyzeTestRun()
            res = analyzeTestRun2()
            if case .new(let unitInfo) = res {
                var cur = Set(unitInfo.initiallyUniqueFeatures.map { $0.pcGroup } + unitInfo.initiallyReplacingBestUnitForFeatures.map { $0.pcGroup })
                guard !cur.isEmpty else {
                    fatalError("Somehow the unit was classified as `new` but it doesn't have new pcgroups")
                }
                if previousUniquePCGroups.isEmpty {
                    guard i == 0 else {
                        fatalError("previousUniquePCGroups is empty but it is not the first loop itreatot")
                    }
                    print("Found new features")
                    previousUniquePCGroups = cur
                    tryAgain = true
                }
                else if previousUniquePCGroups == cur {

                    tryAgain = false
                }
                else {
                    let diff = previousUniquePCGroups.symmetricDifference(cur)
                    guard !diff.isEmpty else {
                        fatalError("the diff is empty, that's strange")
                    }
                    for pcGroup in diff {
                        print("Forbidding \(pcGroup)")
                        let (inserted, _) = info.corpus.forbiddenPCGroups.insert(pcGroup)
                        print("Was forbidden before: \(!inserted)")
                        cur.remove(pcGroup)
                    }
                    previousUniquePCGroups = cur
                    if previousUniquePCGroups.isEmpty {
                        print("It turns out after removing the non-deterministic features, this input was not interesting")
                        tryAgain = false
                    } else {
                        print("I'm done forbidding things. i =", i)
                        tryAgain = true
                    }
                }
            } else {
                if i != 0 {
                    print("This time we didn't find any new features for that unit. I guess that means all of its pc groups are not deterministic?")
                    for c in previousUniquePCGroups {
                        print("Forbidding \(c)")
                        let (inserted, _) = info.corpus.forbiddenPCGroups.insert(c)
                        print("Was forbidden before: \(!inserted)")
                    }
                    previousUniquePCGroups = []
                    i = -1
                    tryAgain = true
                } else {
                    break Loop
                }
            }
        }
        if i > 1 {
            print("end with i:", i)
        }
        
        updateCorpusAfterAnalysis(result: res)
        info.updateStatsAfterRunAnalysis()
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
            analyze()
        }
        
        info.state = .didReadCorpora
    }
    
    
    
    public func determinismLoop() {
        print("Start mutate")
        for _ in 0 ..< 100 {
            _ = fuzzTest.mutators.mutate(&info.unit, &info.world.rand)
        }
        
        var features: [Feature] = []
        print("Start initial test")
        info.state = .willRunTest
        print(hexString(info.unit.hash()))
        runTest()
        info.state = .willRunTest
        runTest()
        info.state = .willRunTest
        runTest()
        print("Start initial collect features")
        TracePC.collectFeatures(debug: false) { features.append($0) }
        print("Start loop")
        while true {
            info.state = .willRunTest
            print(hexString(info.unit.hash()))
            runTest()
            var otherFeatures: [Feature] = []
            TracePC.collectFeatures(debug: false) { otherFeatures.append($0) }
            guard features.count == otherFeatures.count, features == otherFeatures else {
                print("Test function is not deterministic")
                print("runs: ", info.stats.totalNumberOfRuns)
                
                print("Features:")
                var c: [Feature?] = features.filter { !otherFeatures.contains($0) }.map { .some($0) }
                var d: [Feature?] = otherFeatures.filter { !features.contains($0) }.map { .some($0) }
                
                c += repeatElement(nil, count: max(0, d.count - c.count))
                d += repeatElement(nil, count: max(0, c.count - d.count))
                
                zip(c, d).forEach { print($0.0.map { x in "\(x)" } ?? "nil", $0.1.map { x in "\(x)" } ?? "nil") }
                
                print("Unit:")
                print(info.unit)
                fatalError()
            }
        }
    }
}
