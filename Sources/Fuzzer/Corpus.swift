
import Darwin

extension Optional: FuzzUnit where Wrapped: FuzzUnit {
    public func complexity() -> Complexity {
        switch self {
        case .none: return 0.0
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

struct CorpusIndex: Hashable {
    var value: Int
}

extension Fuzzer {
    struct Corpus {
        
        struct UnitInfo {
            var unit: FT.Unit?
            var coverageScore: Feature.Coverage.Score
            var mayDeleteFile: Bool
            var reduced: Bool
            var uniqueFeaturesSet: [Feature.Key]
        }
        
        var units: [UnitInfo] = []
        
        var cumulativeWeights: [UInt64] = []
        
        var addedCoverageScore: Feature.Coverage.Score = .init(0)
        
        var unitInfoForFeature = FeatureDictionary.createEmpty()
    }
}

extension Fuzzer.Corpus {
    mutating func updateCumulativeWeights() {
        cumulativeWeights = units.enumerated().scan(0, { (weight, next) in
            let (offset, unit) = next
            return weight + UInt64(unit.coverageScore.s) * UInt64(offset+1)
        })
    }
    
    mutating func replace(_ unitIndex: CorpusIndex, with unit: FT.Unit) {
        
        var oldUnitInfo = units[unitIndex.value]
        precondition(unit.complexity() < oldUnitInfo.unit.complexity())
        
        Fuzzer.Effect.deleteFile(unitInfo: units[unitIndex.value])
        
        oldUnitInfo.unit = unit
        oldUnitInfo.reduced = true
        
        units[unitIndex.value] = oldUnitInfo
    }
    
    mutating func chooseUnitIdxToMutate(_ r: inout Rand) -> CorpusIndex {
        let x = r.weightedPickIndex(cumulativeWeights: cumulativeWeights)
        return CorpusIndex(value: x)
    }
    
    func numActiveUnits() -> Int {
        return units.reduce(0) { $0 + ($1.unit != nil ? 1 : 0) }
    }

    mutating func deleteUnit(_ idx: CorpusIndex) {
        let unitInfo = units[idx.value]
        Fuzzer.Effect.deleteFile(unitInfo: unitInfo)
        print("EVICTED \(hashToString(unitInfo.unit.hash()))")
        units[idx.value].unit = nil
        // if debug only
        
    }
}
