
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

public func hexString(_ h: Int) -> String {
    let bits = UInt64(bitPattern: Int64(h))
    return String(bits, radix: 16, uppercase: false)
}

struct CorpusIndex: Hashable {
    var value: Int
}

extension FuzzerInfo {
    final class Corpus {
        
        struct UnitInfo {
            var unit: T?
            var coverageScore: Feature.Coverage.Score
            var mayDeleteFile: Bool
            var reduced: Bool
            var uniqueFeaturesSet: [Feature]
        }
        var units: [UnitInfo] = []
        var cumulativeWeights: [UInt64] = []
        var coverageScore: Feature.Coverage.Score = .init(0)
        var unitInfoForFeature = FeatureDictionary.createEmpty()
    }
}

extension FuzzerInfo.Corpus {
    func updateCumulativeWeights() {
        cumulativeWeights = units.enumerated().scan(0, { (weight, next) in
            let (offset, unit) = next
            return weight + UInt64(unit.coverageScore.s) * UInt64(offset+1)
        })
    }
    
    func replace(_ unitIndex: CorpusIndex, with unit: T) -> (inout World) throws -> Void {
        
        var oldUnitInfo = units[unitIndex.value]
        precondition(unit.complexity() < oldUnitInfo.unit.complexity())
        
        let _oldUnit = oldUnitInfo.unit
        oldUnitInfo.unit = unit
        oldUnitInfo.reduced = true
        
        units[unitIndex.value] = oldUnitInfo
        
        guard let oldUnit = _oldUnit else { fatalError("Replacing a unit that doesn't exist") }
        
        return { w in
            try w.removeFromOutputCorpus(oldUnit)
        }
    }
    
    func chooseUnitIdxToMutate(_ r: inout Rand) -> CorpusIndex {
        let x = r.weightedPickIndex(cumulativeWeights: cumulativeWeights)
        return CorpusIndex(value: x)
    }
    
    func numActiveUnits() -> Int {
        return units.reduce(0) { $0 + ($1.unit != nil ? 1 : 0) }
    }

    func deleteUnit(_ idx: CorpusIndex) -> (inout World) throws -> Void {
        guard let oldUnit = units[idx.value].unit else {
            fatalError("Deleting a unit that doesn't exist")
        }
        units[idx.value].unit = nil
        
        return { w in
            try w.removeFromOutputCorpus(oldUnit)
        }
    }
}
