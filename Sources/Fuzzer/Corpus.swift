
extension Optional: FuzzInput where Wrapped: FuzzInput {
    public func complexity() -> Int {
        switch self {
        case .none: return 0
        case .some(let w): return w.complexity()
        }
    }
    public func hash() -> Int {
        switch self {
        case .none: return 0
        case .some(let w): return w.hash()
        }
    }
}

struct Interval {
    
}

func hashToString(_ h: Int) -> String {
    return String(h, radix: 16, uppercase: false)
}

struct Corpus <FI: FuzzInput> {

    struct InputInfo {
        var unit: FI?
        var numFeatures: Int
        var tmp: Int
        var numExecutedMutations: Int
        var numSuccessfulMutations: Int
        var mayDeleteFile: Bool
        var reduced: Bool
        var uniqueFeaturesSet: [Feature]
    }
    
    // TODO: piecewise constant distribution
    
    var intervals: [Interval]
    var weights: [Double]
    
    var hashes: Set<Int>
    var inputs: [InputInfo]
    
    var numAddedFeatures: Int
    var numUpdatedFeatures: Int
    
    var perFeature: FixedSizeArray<(inputComplexity: Int, simplestElement: Int)>
    
    var outputCorpus: String
    
    func maxInputComplexity() -> Int {
        return inputs.max(by: { $0.unit.complexity() < $1.unit.complexity() })?.unit.complexity() ?? 0
    }
    
    mutating func addToCorpus(unit: FI, numFeatures: Int, mayDeleteFile: Bool, featureSet: [Feature]) {
        let info = InputInfo.init(
            unit: unit,
            numFeatures: numFeatures,
            tmp: 0,
            numExecutedMutations: 0,
            numSuccessfulMutations: 0,
            mayDeleteFile: mayDeleteFile,
            reduced: false,
            uniqueFeaturesSet: featureSet
        )
        inputs.append(info)
        hashes.insert(unit.hash()) // that makes no sense to me
        // TODO: update corpus distribution
    }
    
    mutating func replace(_ inputIdx: Int, with unit: FI) {
        var input = inputs[inputIdx]
        assert(unit.complexity() < input.unit.complexity())
        hashes.remove(input.unit.hash())
        
        // TODO: delete file
        
        hashes.insert(unit.hash())
        input.unit = unit
        input.reduced = true
        
        inputs[inputIdx] = input
    }
    
    func hasUnit(_ u: FI) -> Bool {
        return hashes.contains(u.hash())
    }
    
    func chooseUnitIdxToMutate(_ r: inout Rand) -> Int {
        let weightedInputs = Array(zip(inputs.indices, inputs.map { UInt64($0.numFeatures) }))
        return r.weightedPick(from: weightedInputs)
    }
    
    func printStats() {
        for (x, i) in zip(inputs, inputs.indices) {
            print(
            """
                [\(i) \(hashToString(x.unit.hash()))] complexity: \(x.unit.complexity())    executed_mutations: \(x.numExecutedMutations) successful_mutations: \(x.numSuccessfulMutations)
            """)
        }
    }
    func printFeatureSet() {
        for (i, (inputComplexity: complexity, simplestElement: simplestElement)) in zip(perFeature.indices, perFeature) where complexity != 0 {
            print("[\(i): id \(simplestElement) complexity: \(complexity)]")
        }
        print()
        for (x, i) in zip(inputs, inputs.indices) where x.numFeatures != 0 {
            print(" \(i)=>\(x.numFeatures)")
        }
        print()
    }

    mutating func addFeature(idx: Int, newComplexity: Int, shrink: Bool) -> Bool {
        let idx = idx % perFeature.count
        let (oldComplexity, oldIdx) = perFeature[idx]
        guard oldComplexity == 0 || (shrink && oldComplexity > newComplexity) else {
            return false
        }
        if oldComplexity > 0 {
            inputs[oldIdx].numFeatures -= 1
            if inputs[oldIdx].numFeatures == 0 {
                deleteInput(oldIdx)
            }
        } else {
            numAddedFeatures += 1
        }
        numAddedFeatures += 1
        // TODO: DEBUG
        perFeature[idx] = (inputComplexity: newComplexity, simplestElement: inputs.count)
        
        return true
    }
    
    mutating func deleteFile(input: InputInfo) {
        // TODO: delete file
    }

    mutating func deleteInput(_ idx: Int) {
        let input = inputs[idx]
        deleteFile(input: input)
        inputs[idx].unit = nil
        // TODO: WHAT ABOUT THE OTHER FIELDS?
        // if debug only
        // print("EVICTED \(idx)")
    }
    
    mutating func resetFeatureSet() {
        assert(inputs.isEmpty)
        perFeature.reset(to: (inputComplexity: 0, simplestElement: 0))
    }
    
    mutating func validateFeatureSet() {
        // TODO: debug
        for x in perFeature where x.inputComplexity != 0 {
            inputs[x.simplestElement].tmp += 1
        }
        for (input, i) in zip(inputs, inputs.indices) {
            if input.tmp != input.numFeatures {
                print("ZZZ \(input.tmp) \(input.numFeatures)")
            }
            assert(input.tmp == input.numFeatures)
            inputs[i].tmp = 0
        }
    }
}
