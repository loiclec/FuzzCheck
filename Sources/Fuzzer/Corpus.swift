
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

enum CorpusIndex: Hashable {
    case normal(Int)
}

extension FuzzerInfo {
    final class Corpus {
        
        struct UnitInfo: Codable {
            var unit: T?
            var coverageScore: Feature.Coverage.Score
            var uniqueFeaturesSet: [Feature]
        }

        var numActiveUnits = 0
        var units: [UnitInfo] = []
        var cumulativeWeights: [UInt64] = []
        var coverageScore: Feature.Coverage.Score = 0
        var unitInfoForFeature = FeatureDictionary.createEmpty()
    }
}

extension FuzzerInfo.Corpus {
    subscript(idx: CorpusIndex) -> UnitInfo {
        get {
            switch idx {
            case .normal(let idx):
                return units[idx]
            }
        }
        set {
            switch idx {
            case .normal(let idx):
                units[idx] = newValue
            }
        }
    }
}

extension FuzzerInfo.Corpus {
    func append(_ unitInfo: UnitInfo) {
        self.units.append(unitInfo)
        self.numActiveUnits += 1
    }
}

extension FuzzerInfo.Corpus {
    func updateCumulativeWeights() {
        cumulativeWeights = units.enumerated().scan(0, { (weight, next) in
            let (offset, unit) = next
            return weight + UInt64(unit.coverageScore.value) * UInt64(offset+1)
        })
    }
    
    func replace(_ unitIndex: CorpusIndex, with unit: T) -> (inout World) throws -> Void {
        guard case .normal(let idx) = unitIndex else {
            fatalError("Cannot delete special corpus unit.")
        }
        var oldUnitInfo = units[idx]
        precondition(unit.complexity() < oldUnitInfo.unit.complexity())
        
        let _oldUnit = oldUnitInfo.unit
        oldUnitInfo.unit = unit
        
        units[idx] = oldUnitInfo
        
        guard let oldUnit = _oldUnit else { fatalError("Replacing a unit that doesn't exist") }
        
        return { w in
            try w.removeFromOutputCorpus(oldUnit)
        }
    }
    
    func chooseUnitIdxToMutate(_ r: inout Rand) -> CorpusIndex {
        let x = r.weightedPickIndex(cumulativeWeights: cumulativeWeights)
        return .normal(x)
    }

    func deleteUnit(_ idx: CorpusIndex) -> (inout World) throws -> Void {
        guard case .normal(let idx) = idx else {
            fatalError("Cannot delete special corpus unit.")
        }
        guard let oldUnit = units[idx].unit else {
            fatalError("Deleting a unit that doesn't exist")
        }
        units[idx].unit = nil
        numActiveUnits -= 1
        return { w in
            try w.removeFromOutputCorpus(oldUnit)
        }
    }
}
