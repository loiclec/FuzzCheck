
import Darwin

struct Fuzzer <F: FuzzTarget> {
    var rand: Rand
    var uniqueFeaturesSet: Set<Feature>
    var corpus: Corpus<F.Input>
    
    var totalNumberOfRuns: Int
    
    var startTime: clock_t
    var stopTime: clock_t
    
    let shrink: Bool
    let reduceInputs: Bool
}

extension Fuzzer {
    mutating func runOne(_ f: F, mayDeleteFile: Bool, inputInfoIdx: Int?) -> Bool {
        let input = f.newInput(&rand)
        
       executeCallback(f)
        
        uniqueFeaturesSet.removeAll()
        var foundUniqueFeaturesOfII = 0
        let numUpdatesBefore = corpus.numUpdatedFeatures
        
        TPC.collectFeatures { feature in
            if corpus.addFeature(idx: feature, newComplexity: input.complexity(), shrink: shrink) {
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
            corpus.addToCorpus(unit: input, numFeatures: numNewFeatures, mayDeleteFile: mayDeleteFile, featureSet: Array(uniqueFeaturesSet))
            return true
        }
        
        if let iiIdx = inputInfoIdx,
            case let ii = corpus.inputs[iiIdx],
            foundUniqueFeaturesOfII != 0,
            ii.uniqueFeaturesSet.count != 0,
            foundUniqueFeaturesOfII == ii.uniqueFeaturesSet.count,
            ii.unit.complexity() > input.complexity()
        {
            corpus.replace(iiIdx, with: input)
            return true
        }
        return false
    }
    
    mutating func executeCallback(_ f: F) {
        // TODO: record initial stack
        totalNumberOfRuns += 1
        // assert in fuzzing thread
        // shared memory thingy
        
        TPC.resetMaps()
        
        startTime = clock()
        
        // runningCB = true
        let res = f.run(f.newInput(&rand))
        assert(res == 0)
        // runningCB = false
        
        stopTime = clock()
    }
}

public func noop <T> (_ t: T) { }
