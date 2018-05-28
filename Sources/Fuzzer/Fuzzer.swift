
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

public struct Fuzzer <FT: FuzzTest> {
    
    var corpus: Corpus<FT.Unit> = Corpus()
    var totalNumberOfRuns: Int = 0
    var currentUnit: FT.Unit = FT.baseUnit()
    var startTime: UInt = 0
    var stopTime: UInt = 0
    var runningTest: Bool = false
    
    var numberOfNewUnitsAdded: Int = 0
    
    var maxInputComplexity: UInt64 = 0
    let shuffleAtStartup: Bool = true
    let defaultMaxInputComplexity: UInt64 = 256
    let mutateDepth: Int = 3
    let maxNumberOfRuns: Int = Int.max
    let reduceInputs: Bool = true
    let shrink: Bool = true
    var coeffects: Coeffects
    let fuzzTarget: FT
    var processStartTime: UInt = 0
    let timeout: Int32 = Int32.max
    
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
    
    var state: State

    public init(fuzzTarget: FT, seed: UInt32) {
        self.state = .initial
        self.fuzzTarget = fuzzTarget
        self.coeffects = Coeffects(rand: Rand(seed: seed))
        coordinator._send = self.receive
        setSignalHandler(timeout: timeout)
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

extension Fuzzer {
    
    enum ProgramCounterTracer {
        static func resetMaps() {
            TPC.resetMaps()
        }
        static func collectFeatures(_ handle: (Feature) -> Void) {
            TPC.collectFeatures(handle)
        }
        static func totalPCCoverage() -> Int {
            return TPC.getTotalPCCoverage()
        }
    }
    
    struct Coeffects {
        func clock() -> UInt {
            return Darwin.clock()
        }
        func peakRssMB() -> Int {
            var r: rusage = rusage.init()
            if getrusage(RUSAGE_SELF, &r) != 0 {
                return 0
            }
            return r.ru_maxrss >> 20
        }
        
        func readInputCorpus() -> [FT.Unit] {
            let inputCorpus = "Corpus/"
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: inputCorpus) else {
                print("Could not read contents of \(inputCorpus)")
                preconditionFailure()
            }
            var units: [FT.Unit] = []
            print("Info: \(files.count) found in \(inputCorpus)")
            for f in files {
                let decoder = JSONDecoder()
                guard
                    let data = FileManager.default.contents(atPath: "\(inputCorpus)/\(f)"),
                    let unit = try? decoder.decode(FT.Unit.self, from: data)
                    else {
                        print("Could not decode file \(f)")
                        preconditionFailure()
                        continue
                }
                units.append(unit)
            }
            return units
        }
        
        var rand: Rand
    }
    
    enum Effect {
        static func reportStats(updateKind: UpdateKind, totalNumberOfRuns: Int, totalPCCoverage: Int, score: Feature.Coverage.Score, corpusSize: Int, execPerSec: Double, rss: Int) {
            print(updateKind, terminator: "    ")
            print("\(totalNumberOfRuns) |", terminator: "    ")
            print("cov: \(totalPCCoverage)", terminator: "    ")
            print("score: \(score)", terminator: "    ")
            print("corp: \(corpusSize)", terminator: "    ")
            print("exec/s: \(Int(execPerSec))", terminator: "    ")
            print("rss: \(rss)")
        }
        
        static func writeToOutputCorpus(_ unit: FT.Unit) {
            let outputCorpus = "Corpus"
            let path = "\(outputCorpus)/\(hashToString(unit.hash()))"
            let encoder = JSONEncoder()
            do {
                let data = try encoder.encode(unit)
                guard FileManager.default.createFile(atPath: path, contents: data, attributes: nil) else {
                    throw NSError() // TODO
                }
            } catch let e {
                print(e)
            }
        }
        static func dumpUnit(prefix: String, reason: StopReason, unit: FT.Unit) {
            // print mutation sequence
            print("Base unit: \(hashToString(unit.hash()))")
            print(unit)
            writeUnitToFileWithPrefix(prefix + reason.description, unit: unit)
        }
        
        static func writeUnitToFileWithPrefix(_ prefix: String, unit: FT.Unit) {
            let path = prefix + hashToString(unit.hash())
            let encoder = JSONEncoder()
            do {
                let data = try encoder.encode(unit)
                guard FileManager.default.createFile(atPath: path, contents: data, attributes: nil) else {
                    throw NSError.init()
                }
            } catch let e {
                print(e)
            }
            print("artifact_prefix=\(prefix)")
            print("Test unit written to \(path)")
        }
        
        static func report(signal: Coordinator.Signal) {
            switch signal {
            case .alarm:
                print("\n================ TIMEOUT ================")
            case .crash:
                print("\n================ CRASH DETECTED ================")
            case .fileSizeExceed:
                print("\n================ FILE SIZE EXCEEDED ================")
            case .interrupt:
                print("\n================ RUN INTERRUPTED ================")
            }
        }
    }
}

enum StopReason: CustomStringConvertible {
    case crash
    case timeout
    
    var description: String {
        switch self {
        case .crash: return "crash"
        case .timeout: return "timeout"
        }
    }
}

enum UpdateKind: CustomStringConvertible {
    case new
    case reduce
    case start
    case didReadCorpus
    case done
    
    var description: String {
        switch self {
        case .new:
            return "NEW"
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
    mutating func runTest() {
        guard case .willRunTest = state else { preconditionFailure() }
        
        ProgramCounterTracer.resetMaps()
        
        let startTime = coeffects.clock()
        state = .runningTest(startTime: startTime)
        
        _ = fuzzTarget.run(currentUnit)
        
        state = .didRunTest(timeTaken: coeffects.clock() - startTime)

        totalNumberOfRuns += 1
    }
    
    mutating func analyzeTestRun() {
        guard case .willAnalyzeTestRun(let analysisKind) = state else {
            preconditionFailure()
        }
        
        var uniqueFeaturesSetTmp: [Feature.Key] = []
        let updateScoreBefore = corpus.updatedCoverageScore
        
        let currentUnitComplexity = currentUnit.complexity()
        
        ProgramCounterTracer.collectFeatures { feature in
            if corpus.addFeature(feature, newComplexity: currentUnitComplexity, shrink: shrink) {
                uniqueFeaturesSetTmp.append(feature.key)
            }
        }
        
        let deltaScore = Feature.Coverage.Score(s: corpus.updatedCoverageScore.s - updateScoreBefore.s)
        guard deltaScore.s == 0 else {
            corpus.addToCorpus(unit: currentUnit, coverageScore: deltaScore, mayDeleteFile: analysisKind.mayDeleteFile, featureSet: uniqueFeaturesSetTmp)
            state = .didAnalyzeTestRun(didUpdateCorpus: true)
            return
        }
        uniqueFeaturesSetTmp.sort()

        if
            reduceInputs,
            case .loopIteration(mutatingUnitIndex: let uidx) = analysisKind,
            case let unitInfo = corpus.inputs[uidx.value],
            unitInfo.uniqueFeaturesSet.count != 0,
            uniqueFeaturesSetTmp == unitInfo.uniqueFeaturesSet,
            unitInfo.unit.complexity() > currentUnitComplexity
        {
            corpus.replace(uidx.value, with: currentUnit)
            state = .didAnalyzeTestRun(didUpdateCorpus: true)
        }
        
        state = .didAnalyzeTestRun(didUpdateCorpus: false)
    }
   
    mutating func mutateAndTestOne() {
        guard case .willMutateAndTestOne = state else {
            preconditionFailure()
        }
        let idx = corpus.chooseUnitIdxToMutate(&coeffects.rand)
        let unit = corpus.inputs[idx.value].unit ?? fuzzTarget.newUnit(&coeffects.rand) // TODO: is this correct?
        currentUnit = unit
        
        for _ in 0 ..< mutateDepth {
            guard totalNumberOfRuns < maxNumberOfRuns else { break }
            guard fuzzTarget.mutators.mutate(&currentUnit, &coeffects.rand) else { break }
            
            corpus.inputs[idx.value].numExecutedMutations += 1

            state = .willRunTest

            runTest()
            
            state = .willAnalyzeTestRun(.loopIteration(mutatingUnitIndex: idx))
            analyzeTestRun()

            guard case .didAnalyzeTestRun(let updatedCorpus) = state else { preconditionFailure() }
            
            if updatedCorpus {
                corpus.inputs[idx.value].numSuccessfulMutations += 1
                numberOfNewUnitsAdded += 1
                reportStatus(corpus.inputs[idx.value].reduced ? .reduce : .new)
                Effect.writeToOutputCorpus(currentUnit)
            }
        }
    }

    public mutating func loop() {
        reportStatus(.start)
        readAndExecuteCorpora()
        reportStatus(.didReadCorpus)
    
        while totalNumberOfRuns < maxNumberOfRuns {
            state = .willMutateAndTestOne
            mutateAndTestOne()
        }
        state = .done
        reportStatus(.done)
    }
    
    func reportStatus(_ updateKind: UpdateKind) {
        let now = coeffects.clock()
        let seconds = Double(now - processStartTime) / 1_000_000

        Effect.reportStats(
            updateKind: updateKind,
            totalNumberOfRuns: totalNumberOfRuns,
            totalPCCoverage: ProgramCounterTracer.totalPCCoverage(),
            score: corpus.addedCoverageScore,
            corpusSize: corpus.numActiveUnits(),
            execPerSec: (Double(totalNumberOfRuns) / seconds).rounded(),
            rss: coeffects.peakRssMB()
        )
    }
    
    mutating func readAndExecuteCorpora() {
        var units = [FT.baseUnit()]
        units += coeffects.readInputCorpus()
        /*
        let complexities = units.map { $0.complexity() }
        let totalComplexity = complexities.reduce(0) { $0 + $1 }
        let maxUnitComplexity = complexities.reduce(0.0) { max($0, $1) }
        let minUnitComplexity = complexities.reduce(Double.greatestFiniteMagnitude) { min($0, $1) }
        
        if maxInputComplexity == 0 {
            maxInputComplexity = defaultMaxInputComplexity
        }
        // TODO: print
        */
        
        if shuffleAtStartup {
            coeffects.rand.shuffle(&units)
        }
        // TODO: prefer small
        
        for u in units {
            // TODO: max complexity
            currentUnit = u
            state = .willRunTest
            runTest()
            state = .willAnalyzeTestRun(.readingCorpus)
            analyzeTestRun()
        }
        state = .didReadCorpora
    }
    
    func receive(signal: Coordinator.Signal) {
        switch signal {
        case .crash:
            Effect.report(signal: signal)
            // external func print stack trace
            Effect.dumpUnit(prefix: "crash-", reason: .crash, unit: currentUnit)
            self.reportStatus(.done)
            exit(1)
            
        case .alarm:
            precondition(timeout > 0)
            guard case .runningTest = state else { return } // We have not started running units yet.
            let microseconds = clock() - startTime
            guard microseconds > timeout else { return }
            Effect.report(signal: signal)
            print(
                """
                Alarm: working on the last Unit for \(microseconds / 1000) milliseconds
                and the timeout value is \(timeout / 1000) (use -timeout=N to change)
                """)
            Effect.dumpUnit(prefix: "timeout-", reason: .timeout, unit: currentUnit)
            reportStatus(.done)
            exit(1)
            
        case .fileSizeExceed:
            Effect.report(signal: signal)
            exit(1)
            
        case .interrupt:
            Effect.report(signal: signal)
            reportStatus(.done)
            exit(0)
        }
    }
}
















