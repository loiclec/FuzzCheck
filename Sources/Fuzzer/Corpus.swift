
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

struct CorpusIndex: Equatable {
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
        
        var hashes: Set<Int> = []
        var units: [UnitInfo] = []
        
        var cumulativeWeights: [UInt64] = []
        
        var addedCoverageScore: Feature.Coverage.Score = .init(s: 0)
        var updatedCoverageScore: Feature.Coverage.Score = .init(s: 0)
        
        var unitInfoForFeature = FeatureDictionary.createEmpty()
    }
}

extension Fuzzer.Corpus {
    
    mutating func addToCorpus(unit: FT.Unit, coverageScore: Feature.Coverage.Score, mayDeleteFile: Bool, featureSet: [Feature.Key]) {
        let info = UnitInfo(
            unit: unit,
            coverageScore: coverageScore,
            mayDeleteFile: mayDeleteFile,
            reduced: false,
            uniqueFeaturesSet: featureSet
        )
        units.append(info)
        hashes.insert(unit.hash())
        
        updateCumulativeWeights()
    }
    
    mutating func updateCumulativeWeights() {
        cumulativeWeights.removeAll()
        cumulativeWeights = units.enumerated().scan(0, { (weight, next) in
            let (offset, unit) = next
            return weight + UInt64(unit.coverageScore.s) * UInt64(offset+1)
        })
    }
    
    mutating func replace(_ unitIndex: CorpusIndex, with unit: FT.Unit) {
        
        var oldUnitInfo = units[unitIndex.value]
        precondition(unit.complexity() < oldUnitInfo.unit.complexity())
        hashes.remove(oldUnitInfo.unit.hash())
        
        Fuzzer.Effect.deleteFile(unitInfo: units[unitIndex.value])
        
        hashes.insert(unit.hash())
        oldUnitInfo.unit = unit
        oldUnitInfo.reduced = true
        
        units[unitIndex.value] = oldUnitInfo
    }
    
    func hasUnit(_ u: FT.Unit) -> Bool {
        return hashes.contains(u.hash())
    }
    
    mutating func chooseUnitIdxToMutate(_ r: inout Rand) -> CorpusIndex {
        let x = r.weightedPickIndex(cumulativeWeights: cumulativeWeights)
        return CorpusIndex(value: x)
    }
    
    func numActiveUnits() -> Int {
        return units.reduce(0) { $0 + ($1.unit != nil ? 1 : 0) }
    }
    
    mutating func addFeature(_ feature: Feature, newComplexity: Complexity, shrink: Bool) -> Bool {
        precondition(newComplexity != 0.0)
        let unitInfo = unitInfoForFeature[feature.key]
        
        if case (let oldC, _)? = unitInfo {
            guard shrink && oldC.value > newComplexity.value else {
                return false
            }
        }

        let covScore = feature.coverage.importance
        
        if case let (_, oldSmallestElementIdx)? = unitInfo {
            units[oldSmallestElementIdx.value].coverageScore.s -= covScore.s
            if units[oldSmallestElementIdx.value].coverageScore.s == 0 {
                deleteUnit(oldSmallestElementIdx)
            }
        } else {
            addedCoverageScore.s += covScore.s
        }
        updatedCoverageScore.s += covScore.s
        
        unitInfoForFeature[feature.key] = (newComplexity, CorpusIndex(value: units.count))
        
        return true
    }

    mutating func deleteUnit(_ idx: CorpusIndex) {
        let unitInfo = units[idx.value]
        Fuzzer.Effect.deleteFile(unitInfo: unitInfo)
        units[idx.value].unit = nil
        // if debug only
        // print("EVICTED \(idx)")
    }
}
