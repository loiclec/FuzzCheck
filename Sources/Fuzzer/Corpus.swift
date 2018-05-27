
import Foundation

extension Optional: FuzzInput where Wrapped: FuzzInput {
    public func complexity() -> Double {
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

func hashToString(_ h: Int) -> String {
    let bits = UInt64(bitPattern: Int64(h))
    return String(bits, radix: 16, uppercase: false)
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
    
    var hashes: Set<Int> = []
    var inputs: [InputInfo] = []
    
    var cumulativeWeights: [UInt64] = []
    
    var numAddedFeatures: Int = 0
    var numUpdatedFeatures: Int = 0
    
    var perFeature: FixedSizeArray<(inputComplexity: Double, simplestElement: Int)> = FixedSizeArray(repeating: (0, 0), count: 1 << 21)
    
    var outputCorpus: String = "Corpus" // TODO
    
    func maxInputComplexity() -> Double {
        return inputs.max(by: { $0.unit.complexity() < $1.unit.complexity() })?.unit.complexity() ?? 0.0
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
        hashes.insert(unit.hash())
        
        validateFeatureSet()
        updateCumulativeWeights()
    }
    
    mutating func updateCumulativeWeights() {
        cumulativeWeights.removeAll()
        cumulativeWeights = inputs.enumerated().scan(0, { $0 + UInt64($1.element.numFeatures) * UInt64($1.offset+1) })
    }
    
    mutating func replace(_ inputIdx: Int, with unit: FI) {
        
        var input = inputs[inputIdx]
        precondition(unit.complexity() < input.unit.complexity())
        hashes.remove(input.unit.hash())
        
        deleteFile(input: inputs[inputIdx])
        
        hashes.insert(unit.hash())
        input.unit = unit
        input.reduced = true
        
        inputs[inputIdx] = input
    }
    
    func hasUnit(_ u: FI) -> Bool {
        return hashes.contains(u.hash())
    }
    
    mutating func chooseUnitIdxToMutate(_ r: inout Rand) -> Int {
        let x = r.weightedPickIndex(cumulativeWeights: cumulativeWeights)
        return x
        //return r.weightedPickIndex(cumulativeWeights: cumulativeWeights)
    }
    
    func numActiveUnits() -> Int {
        return inputs.reduce(0) { $0 + ($1.unit != nil ? 1 : 0) }
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

    var uniqueFeaturesHere: Set<Int> = []
    
    mutating func addFeature(idx: Int, newComplexity: Double, shrink: Bool) -> Bool {
        let idx = idx % perFeature.count

        let (oldComplexity, oldSmallestElementIdx) = perFeature.array[idx]
        guard oldComplexity == 0 || (shrink && oldComplexity > newComplexity) else {
            return false
        }
        if oldComplexity > 0 {
            inputs[oldSmallestElementIdx].numFeatures -= 1
            if inputs[oldSmallestElementIdx].numFeatures == 0 {
                deleteInput(oldSmallestElementIdx)
            }
        } else {
            numAddedFeatures += 1
        }
        numUpdatedFeatures += 1
        // TODO: DEBUG
        perFeature.array[idx] = (inputComplexity: newComplexity, simplestElement: inputs.count)
        
        
        
        return true
    }

    mutating func deleteFile(input: InputInfo) {
        guard !outputCorpus.isEmpty, input.mayDeleteFile else { return }
        let path = "\(outputCorpus)/\(hashToString(input.unit.hash()))" // TODO: more robust solution
        unlink(path)

    }

    mutating func deleteInput(_ idx: Int) {
        let input = inputs[idx]
        deleteFile(input: input)
        inputs[idx].unit = nil
        // if debug only
        // print("EVICTED \(idx)")
    }
    
    mutating func resetFeatureSet() {
        precondition(inputs.isEmpty)
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
            precondition(input.tmp == input.numFeatures)
            inputs[i].tmp = 0
        }
    }
}
