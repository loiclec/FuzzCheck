
import Darwin
import Foundation

struct Fuzzer <F: FuzzTarget, M: Mutators> where M.Mutated == F.Input {
    var rand: Rand
    var uniqueFeaturesSet: Set<Feature>
    var corpus: Corpus<F.Input>
    
    var totalNumberOfRuns: Int
    var numberOfNewUnitsAdded: Int
    var lastCorpusUpdateRun: Int
    var lastCorpusUpdateTime: clock_t
    
    let mutateDepth: Int
    let maxNumberOfRuns: Int
    let maxComplexity: Double?
    let minDefaultComplexity: Double
    let shuffleAtStartup: Bool
    
    var maxInputComplexity: Double
    var maxMutationComplexity: Double
    
    var startTime: clock_t
    var stopTime: clock_t
    
    let mutators: M
    
    let userCallback: (F.Input) -> Bool
    
    let shrink: Bool
    let reduceInputs: Bool
}

extension Fuzzer {
    mutating func runOne(_ u: F.Input, mayDeleteFile: Bool, inputInfoIdx: Int?) -> Bool {
        
        executeCallback(u)
        
        uniqueFeaturesSet.removeAll()
        var foundUniqueFeaturesOfII = 0
        let numUpdatesBefore = corpus.numUpdatedFeatures
        
        TPC.collectFeatures { feature in
            if corpus.addFeature(idx: feature, newComplexity: u.complexity(), shrink: shrink) {
                uniqueFeaturesSet.insert(feature)
            }
            if reduceInputs, inputInfoIdx != nil, uniqueFeaturesSet.contains(feature) { // TODO: what is inputInfo exactly?
                foundUniqueFeaturesOfII += 1
            }
        }
        
        // TODO: print pulse and report slow inputs
        
        let numNewFeatures = corpus.numUpdatedFeatures - numUpdatesBefore
        guard numNewFeatures == 0 else {
            TPC.updateObservedPCs()
            corpus.addToCorpus(unit: u, numFeatures: numNewFeatures, mayDeleteFile: mayDeleteFile, featureSet: Array(uniqueFeaturesSet))
            return true
        }
        
        if let iiIdx = inputInfoIdx,
            case let ii = corpus.inputs[iiIdx],
            foundUniqueFeaturesOfII != 0,
            ii.uniqueFeaturesSet.count != 0,
            foundUniqueFeaturesOfII == ii.uniqueFeaturesSet.count,
            ii.unit.complexity() > u.complexity()
        {
            corpus.replace(iiIdx, with: u)
            return true
        }
        return false
    }
    
    mutating func executeCallback(_ u: F.Input) {
        // TODO: record initial stack
        totalNumberOfRuns += 1
        // assert in fuzzing thread
        // shared memory thingy
        
        TPC.resetMaps()
        
        startTime = clock()
        
        // runningCB = true
        let res = userCallback(u)
        assert(res)
        // runningCB = false
        
        stopTime = clock()
    }
    
    mutating func mutateAndTestOne() {
        // TODO: mutation sequence
        let idx = corpus.chooseUnitIdxToMutate(&rand)
        guard var unit = corpus.inputs[idx].unit else {
            fatalError("When can this happen? How to handle it?")
        }
        // TODO: max mutation length
        
        for _ in 0 ..< rand.positiveInt(mutateDepth)+1 {
            guard totalNumberOfRuns < maxNumberOfRuns else { break }
            guard mutators.mutate(&unit, &rand) else { continue }
            corpus.inputs[idx].numExecutedMutations += 1
            if runOne(unit, mayDeleteFile: true, inputInfoIdx: idx) {
                reportNewCoverage(idx, unit)
            }
            // try detecting a memory leak
        }
    }
    
    mutating func reportNewCoverage(_ iiIdx: Int, _ unit: F.Input) {
        corpus.inputs[iiIdx].numSuccessfulMutations += 1
        // record successful mutation sequence
        // print status
        // write output to corpus
        numberOfNewUnitsAdded += 1
        // check exit on source pos or item
        lastCorpusUpdateRun = totalNumberOfRuns
        lastCorpusUpdateTime = clock()
    }
    
    func timedOut() -> Bool {
        // TODO
        return false
    }
    
    mutating func readAndExecuteCorpora(_ dirs: [String]) {
        var units: [F.Input] = []
        for dir in dirs {
            guard let dirFiles = try? FileManager.default.contentsOfDirectory(atPath: dir) else {
                print("Could not read contents of \(dir)")
                assertionFailure()
                continue
            }
            print("Info: \(dirFiles.count) found in \(dir)")
            for f in dirFiles {
                let decoder = JSONDecoder()
                guard
                    let data = FileManager.default.contents(atPath: "\(dir)\(f)"),
                    let unit = try? decoder.decode(F.Input.self, from: data)
                else {
                    print("Could not decode file \(f)")
                    assertionFailure()
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

    mutating func setMaxInputComplexity(_ c: Double) {
        self.maxInputComplexity = c
        self.maxMutationComplexity = c
    }
    mutating func minimizeCrashLoop(_ unit: F.Input) {
        var unit = unit
        guard unit.complexity() > 1 else { return }
        while !timedOut(), totalNumberOfRuns < maxNumberOfRuns {
            guard mutators.mutate(&unit, &rand) else { continue } // TODO: potential for infinite loop here
            executeCallback(unit)
            // print pulse and report slow input
            // try detecting a memory leak
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

public func noop <T> (_ t: T) { }





