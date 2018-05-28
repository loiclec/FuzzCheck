
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

public func hashToString(_ h: Int) -> String {
    let bits = UInt64(bitPattern: Int64(h))
    return String(bits, radix: 16, uppercase: false)
}

struct CorpusIndex: Equatable {
    var value: Int
}

struct Corpus <FI: FuzzInput> {

    struct InputInfo {
        var unit: FI?
        var coverageScore: Feature.Coverage.Score
        var numExecutedMutations: Int
        var numSuccessfulMutations: Int
        var mayDeleteFile: Bool
        var reduced: Bool
        var uniqueFeaturesSet: [Feature.Key]
    }
    
    var hashes: Set<Int> = []
    var inputs: [InputInfo] = []
    
    var cumulativeWeights: [UInt64] = []
    
    var addedCoverageScore: Feature.Coverage.Score = .init(s: 0)
    var updatedCoverageScore: Feature.Coverage.Score = .init(s: 0)
    
    var inputInfoForFeature = FeatureDictionary.createEmpty()
    
    var outputCorpus: String = "Corpus" // TODO
    
    func maxInputComplexity() -> Double {
        return inputs.max(by: { $0.unit.complexity() < $1.unit.complexity() })?.unit.complexity() ?? 0.0
    }
    
    mutating func addToCorpus(unit: FI, coverageScore: Feature.Coverage.Score, mayDeleteFile: Bool, featureSet: [Feature.Key]) {
        let info = InputInfo.init(
            unit: unit,
            coverageScore: coverageScore,
            numExecutedMutations: 0,
            numSuccessfulMutations: 0,
            mayDeleteFile: mayDeleteFile,
            reduced: false,
            uniqueFeaturesSet: featureSet
        )
        inputs.append(info)
        hashes.insert(unit.hash())
        
        print(hashToString(unit.hash()))
        
        updateCumulativeWeights()
    }
    
    mutating func updateCumulativeWeights() {
        cumulativeWeights.removeAll()
        cumulativeWeights = inputs.enumerated().scan(0, { (weight, next) in
            let (offset, input) = next
            return weight + UInt64(input.coverageScore.s) * UInt64(offset+1)
        })
        
        //print(cumulativeWeights)
        //print(inputs.enumerated().map {
        //    (UInt64($0.element.numFeatures) * UInt64($0.offset+1), $0.element.unit.map { u in hashToString(u.hash()) } ?? "nil")
        //})
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
    
    mutating func chooseUnitIdxToMutate(_ r: inout Rand) -> CorpusIndex {
        let x = r.weightedPickIndex(cumulativeWeights: cumulativeWeights)
        return CorpusIndex.init(value: x)
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
        for case (let i, (.magnitudeOf(let complexity), let simplestElement?)) in zip(inputInfoForFeature.indices, inputInfoForFeature) {
            print("[\(i): id \(simplestElement) complexity: \(complexity)]")
        }
        print()
        for (x, i) in zip(inputs, inputs.indices) where x.coverageScore.s != 0 {
            print(" \(i)=>\(x.coverageScore)")
        }
        print()
    }

    var uniqueFeaturesHere: Set<Int> = []
    
    mutating func addFeature(_ feature: Feature, newComplexity: Double, shrink: Bool) -> Bool {
        precondition(newComplexity != 0.0)
        let (oldComplexity, oldSmallestElementIdx) = inputInfoForFeature[feature.key]
        
        if case .magnitudeOf(let oldC) = oldComplexity {
            guard shrink && oldC > newComplexity else {
                return false
            }
        }
        /*
        guard oldComplexity == 0 || (shrink && oldComplexity > newComplexity) else {
            return false
        }

         */
        
        let covScore = feature.coverage.importance
        
        if let oldSmallestElementIdx = oldSmallestElementIdx {
            inputs[oldSmallestElementIdx.value].coverageScore.s -= covScore.s
            if inputs[oldSmallestElementIdx.value].coverageScore.s == 0 {
                deleteInput(oldSmallestElementIdx)
            }
        } else {
            addedCoverageScore.s += covScore.s
        }
        updatedCoverageScore.s += covScore.s
        
        inputInfoForFeature[feature.key] = (inputComplexity: .magnitudeOf(newComplexity), simplestElement: CorpusIndex(value: inputs.count))
        
        return true
    }

    mutating func deleteFile(input: InputInfo) {
        guard !outputCorpus.isEmpty, input.mayDeleteFile else { return }
        let path = "\(outputCorpus)/\(hashToString(input.unit.hash()))" // TODO: more robust solution
        unlink(path)

    }

    mutating func deleteInput(_ idx: CorpusIndex) {
        let input = inputs[idx.value]
        deleteFile(input: input)
        inputs[idx.value].unit = nil
        // if debug only
        // print("EVICTED \(idx)")
    }
    
    mutating func resetFeatureSet() {
        precondition(inputs.isEmpty)
        inputInfoForFeature.assign(repeating: (.zero, nil))
    }
}
