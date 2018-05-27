
import Darwin
import Foundation

public final class Fuzzer <F: FuzzTarget, M: Mutators> where M.Mutated == F.Input {
    var rand: Rand

    var corpus: Corpus<F.Input> = Corpus()
    var currentUnit: F.Input?
    
    var totalNumberOfRuns: Int = 0
    var numberOfNewUnitsAdded: Int = 0
    var lastCorpusUpdateRun: Int = 0
    var lastCorpusUpdateTime: clock_t = 0
    
    let mutateDepth: Int = 3
    let maxNumberOfRuns: Int = 10_000_000
    let maxComplexity: Double? = nil
    let minDefaultComplexity: Double = 256
    let shuffleAtStartup: Bool = false
    let printNew: Bool = true
    let verbosity: Bool = true
    let saveArtifacts: Bool = true
    let artifactsPrefix: String = "crashes/"
    let timeout: Int = 1_000_000
    var processStartTime = clock()
    
    var runningCB = false
    
    var maxInputComplexity: Double = 0.0
    var maxMutationComplexity: Double = 0.0
    
    var startTime: clock_t = 0
    var stopTime: clock_t = 0
    
    let mutators: M
    let fuzzTarget: F
    
    let shrink: Bool = true
    let reduceInputs: Bool = true
    
    public init(mutators: M, fuzzTarget: F, seed: UInt32) {
        print("Seed: \(seed)")
        self.mutators = mutators
        self.fuzzTarget = fuzzTarget
        self.rand = Rand.init(seed: seed)
        coordinator._send = self.receive
        setSignalHandler(timeout: timeout)
    }
}

extension Fuzzer {
    func runOne(_ u: F.Input, mayDeleteFile: Bool, inputInfoIdx: Int?) -> Bool {

        executeCallback(u)

        var uniqueFeaturesSetTmp: Set<Feature> = []
        var foundUniqueFeaturesOfII = 0
        let numUpdatesBefore = corpus.numUpdatedFeatures
        
        
        TPC.collectFeatures { feature in
            if corpus.addFeature(idx: feature, newComplexity: u.complexity(), shrink: shrink) {
                uniqueFeaturesSetTmp.insert(feature)
            }
            if reduceInputs, let iiIdx = inputInfoIdx, corpus.inputs[iiIdx].uniqueFeaturesSet.contains(feature) {
                foundUniqueFeaturesOfII += 1
            }
        }
        // TODO: print pulse and report slow inputs
        
        let numNewFeatures = corpus.numUpdatedFeatures - numUpdatesBefore
        guard numNewFeatures == 0 else {
            //TPC.updateObservedPCs()
            corpus.addToCorpus(unit: u, numFeatures: numNewFeatures, mayDeleteFile: mayDeleteFile, featureSet: Array(uniqueFeaturesSetTmp))
            return true
        }
        
        if let iiIdx = inputInfoIdx,
            case let ii = corpus.inputs[iiIdx],
            foundUniqueFeaturesOfII != 0,
            ii.uniqueFeaturesSet.count != 0,
            foundUniqueFeaturesOfII == ii.uniqueFeaturesSet.count,
            ii.unit.complexity() > u.complexity()
        {
            /*
            print("""
                replace \(corpus.inputs[iiIdx]) by \(u)
                foundUniqueFeaturesOfII: \(foundUniqueFeaturesOfII)
                ii.uniqueFeaturesSet.count: \(ii.uniqueFeaturesSet.count)
                ii.unit.complexity(): \(ii.unit.complexity())
                u.complexity(): \(u.complexity())
                ii.uniqueFeaturesSet: \(ii.uniqueFeaturesSet.sorted())
                uniqueFeaturesSetTmp: \(uniqueFeaturesSetTmp.sorted())
                allFeatures: \(allCollectedFeatures.sorted())
                """)*/
            corpus.replace(iiIdx, with: u)
            return true
        }
        
        return false
    }
    
    func executeCallback(_ u: F.Input) {
        // TODO: record initial stack
        totalNumberOfRuns += 1
        // precondition in fuzzing thread
        // shared memory thingy
        TPC.resetMaps()
        currentUnit = u
        startTime = clock()
        
        runningCB = true
        _ = fuzzTarget.run(currentUnit!)
        runningCB = false
        
        stopTime = clock()
    }
 
    func secondsSinceProcessStartup() -> Double {
        return Double(clock() - processStartTime) / 1_000_000
    }
    
    func execPerSec() -> Double {
        let seconds = secondsSinceProcessStartup()
        return seconds != 0 ? (Double(totalNumberOfRuns) / seconds) : 0
    }
   
    func printStats(_ start: String, _ end: String) {
        guard verbosity else { return }
        
        let execps = execPerSec()
        print("\(totalNumberOfRuns) \(start)", terminator: "")
        print(" cov: \(TPC.getTotalPCCoverage())", terminator: "")
        print(" ft: \(corpus.numAddedFeatures)", terminator: "")
        print(" corp: \(corpus.numActiveUnits())", terminator: "")
        print(" exec/s: \(Int(execps))", terminator: "")
        print(" rss: \(getPeakRSSMb())", terminator: "")
        print(" \(end)")
    }
    
    func printFinalStats() {
        // print/dump coverage
        // TODO: options
        printStats("", "")
        print("number of executed units : \(totalNumberOfRuns)")
        print("average exec per sec     : \(execPerSec())")
        print("new units added          : \(numberOfNewUnitsAdded)")
        print("slowest unit time sec    : \(0)") // TODO
        print("peak rss mb              : \(getPeakRSSMb())")
    }
    
    func printFeatureSet() {
        for (i, x) in zip(corpus.perFeature.indices, corpus.perFeature) where x.inputComplexity != 0 {
            print("[\(i): id \(x.simplestElement) cplx: \(x.inputComplexity.rounded())]")
        }
        for (i, x) in zip(corpus.inputs.indices, corpus.inputs) {
            print("\(i) => \(x.unit.map { "\($0)" } ?? "nil")")
        }
    }
    
    func printStatusForNewUnit(unit: F.Input, text: String) {
        guard printNew else { return }
        printStats(text, "")
        // TODO: complexity and mutation sequence
    }

    func mutateAndTestOne() {
        // TODO: mutation sequence
        let idx = corpus.chooseUnitIdxToMutate(&rand)
        let unit = corpus.inputs[idx].unit ?? fuzzTarget.newInput(&rand) // TODO: is this correct?
        currentUnit = unit
        // TODO: max mutation length
        
        for _ in 0 ..< rand.positiveInt(mutateDepth)+1 {
            guard totalNumberOfRuns < maxNumberOfRuns else { break }
            guard mutators.mutate(&currentUnit!, &rand) else { continue }
            corpus.inputs[idx].numExecutedMutations += 1
            if runOne(currentUnit!, mayDeleteFile: true, inputInfoIdx: idx) {
                reportNewCoverage(idx, currentUnit!)
            }
            // try detecting a memory leak
        }
    }
    
    func reportNewCoverage(_ iiIdx: Int, _ unit: F.Input) {
        corpus.inputs[iiIdx].numSuccessfulMutations += 1
        // record successful mutation sequence
        printStatusForNewUnit(unit: unit, text: corpus.inputs[iiIdx].reduced ? "REDUCE " : "NEW ")
        writeToOutputCorpus(unit: unit)
        numberOfNewUnitsAdded += 1
        // check exit on source pos or item
        lastCorpusUpdateRun = totalNumberOfRuns
        lastCorpusUpdateTime = clock()
    }
    
    func timedOut() -> Bool {
        // TODO
        return false
    }
    
    func readAndExecuteCorpora(_ dirs: [String]) {
        var units: [F.Input] = []
        for dir in dirs {
            guard let dirFiles = try? FileManager.default.contentsOfDirectory(atPath: dir) else {
                print("Could not read contents of \(dir)")
                preconditionFailure()
                continue
            }
            print("Info: \(dirFiles.count) found in \(dir)")
            for f in dirFiles {
                let decoder = JSONDecoder()
                guard
                    let data = FileManager.default.contents(atPath: "\(dir)/\(f)"),
                    let unit = try? decoder.decode(F.Input.self, from: data)
                else {
                    print("Could not decode file \(f)")
                    preconditionFailure()
                    continue
                }
                units.append(unit)
            }
        }
        let complexities = units.map { $0.complexity() }
        let totalComplexity = complexities.reduce(0) { $0 + $1 }
        let maxUnitComplexity = complexities.reduce(0.0) { max($0, $1) }
        let minUnitComplexity = complexities.reduce(Double.greatestFiniteMagnitude) { min($0, $1) }
        
        if maxComplexity == nil {
            setMaxInputComplexity(max(minDefaultComplexity, maxInputComplexity))
        }
        
        defer {
            // Test the callback with empty input and never try it again.
            executeCallback(F.baseInput())
            print("INITED")
            if corpus.inputs.isEmpty {
                print("ERROR: no interesting inputs were found.\nIs the code instrumented for coverage? Exiting.")
                exit(1);
            }
        }
        
        guard !units.isEmpty else {
            print("INFO: A corpus is not provided, starting from an empty corpus");
            let u = F.baseInput()
            _ = runOne(u, mayDeleteFile: false, inputInfoIdx: nil)
            return
        }
        
        print("INFO: seed corpus: units: \(units.count) min: \(minUnitComplexity) max: \(maxUnitComplexity) total: \(totalComplexity) rss: \(getPeakRSSMb())Mb\n")
     
        if shuffleAtStartup {
            rand.shuffle(&units)
        }
        // TODO: prefer small
        
        // Load and execute inputs one by one.
        for u in units where u.complexity() < maxInputComplexity { // how should I really handle max complexity?
            _ = runOne(u, mayDeleteFile: false, inputInfoIdx: nil)
            // check exit on source pos or item
            // try detecting memory leaks
        }
    }

    func setMaxInputComplexity(_ c: Double) {
        self.maxInputComplexity = c
        self.maxMutationComplexity = c
    }
    func minimizeCrashLoop(_ unit: F.Input) {
        guard unit.complexity() > 1 else { return }
        currentUnit = unit
        while !timedOut(), totalNumberOfRuns < maxNumberOfRuns {
            guard mutators.mutate(&currentUnit!, &rand) else { continue } // TODO: potential for infinite loop here
            executeCallback(currentUnit!)
            
            // print pulse and report slow input
            // try detecting a memory leak
        }
    }
    
    public func loop(_ dirs: [String]) {
        processStartTime = clock()
        printStats("START", "")
        readAndExecuteCorpora(dirs)
        printStats("", "")
        // TODO: last corpus reload
        while true {
            // TODO: reload interval sec reload
            guard totalNumberOfRuns < maxNumberOfRuns else { break }
            guard !timedOut() else { break }
            // TODO: len control
            
            mutateAndTestOne()
        }
        print("DONE")
        // print recommended dictionary
    }

    func writeToOutputCorpus(unit: F.Input) {
        guard !corpus.outputCorpus.isEmpty else { return }
        let path = "\(corpus.outputCorpus)/\(hashToString(unit.hash()))"
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(unit)
            guard FileManager.default.createFile(atPath: path, contents: data, attributes: nil) else {
                throw NSError.init()
            }
        } catch let e {
            print(e)
        }
    }
    
    func dumpCurrentUnit(prefix: String) {
        guard let u = currentUnit else { return } // Happens when running individual inputs.
        // print mutation sequence
        print("Base unit: \(hashToString(u.hash()))")
        print(u)
        writeUnitToFileWithPrefix(prefix, unit: u)
    }
    
    func writeUnitToFileWithPrefix(_ prefix: String, unit: F.Input) {
        guard saveArtifacts else { return }
        let path = artifactsPrefix + prefix + hashToString(unit.hash())
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(unit)
            guard FileManager.default.createFile(atPath: path, contents: data, attributes: nil) else {
                throw NSError.init()
            }
        } catch let e {
            print(e)
        }
        print("artifact_prefix=\(artifactsPrefix)")
        print("Test unit written to \(path)")
    }
    
    func receive(signal: Coordinator.Signal) {
        switch signal {
        case .crash:
            print("================ CRASH DETECTED ================")
            // external func print stack trace
            dumpCurrentUnit(prefix: "crash-")
            printFinalStats()
            exit(1)
       
        case .alarm:
            precondition(timeout > 0)
            guard runningCB else { return } // We have not started running units yet.
            let microseconds = clock() - startTime
            // TODO: if verbosity
            guard microseconds > timeout else { return }
            print(
            """
            Alarm: working on the last Unit for \(microseconds / 1000) milliseconds
                   and the timeout value is \(timeout / 1000) (use -timeout=N to change)
            """)
            dumpCurrentUnit(prefix: "timeout-")
            print("================ TIMEOUT AFTER \(microseconds / 1000) milliseconds ================")
            print("SUMMARY: libFuzzer: timeout")
            printFinalStats()
            exit(1) // TODO: exit code
            
        case .fileSizeExceed:
            print("================ FILE SIZE EXCEEDED ================")
            exit(1)
            
        case .interrupt:
            print("================ RUN INTERRUPTED ================")
            printFinalStats()
            exit(0)
        }
    }
}

func getPeakRSSMb() -> Int {
    var r: rusage = rusage.init()
    if getrusage(RUSAGE_SELF, &r) != 0 {
        return 0
    }
    return r.ru_maxrss >> 20
}

public func noop <T> (_ t: T) -> Bool { return true }





