
import Darwin

extension Optional: FuzzUnit where Wrapped: FuzzUnit {
    public func complexity() -> Double {
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
    case favored
}

extension FuzzerInfo {
    final class Corpus {
        
        struct UnitInfo: Codable {
            var unit: T?
            var coverageScore: Double
            let initiallyUniqueFeatures: [Feature]
            let initiallyReplacingBestUnitForFeatures: [Feature]
            let otherFeatures: [Feature]
        }

        var numActiveUnits = 0
        var units: [UnitInfo] = []
        var cumulativeWeights: [UInt64] = []
        var coverageScore: Double = 0
        var allFeatures: [Feature: (Int, Double, CorpusIndex)] = [:]
        
        var forbiddenUnitHashes: Set<Int> = []
        var favoredUnit: UnitInfo? = nil
    }
}

extension FuzzerInfo.Corpus {
    subscript(idx: CorpusIndex) -> UnitInfo {
        get {
            switch idx {
            case .normal(let idx):
                return units[idx]
            case .favored:
                return favoredUnit!
            }
        }
        set {
            switch idx {
            case .normal(let idx):
                units[idx] = newValue
            case .favored:
                fatalError("Cannot assign new unit info to favoredUnit")
            }
        }
    }
}

extension FuzzerInfo.Corpus {
    func append(_ unitInfo: UnitInfo) -> (inout World) throws -> Void {
        precondition(unitInfo.unit != nil)

        let complexity = unitInfo.unit.complexity()
        let index = CorpusIndex.normal(units.endIndex)
        for f in unitInfo.initiallyUniqueFeatures {
            precondition(allFeatures[f] == nil)
            allFeatures[f] = (1, complexity, index)
        }
        for f in unitInfo.initiallyReplacingBestUnitForFeatures {
            let count = allFeatures[f]!.0
            allFeatures[f] = (count + 1, complexity, index)
        }
        for f in unitInfo.otherFeatures {
            allFeatures[f]!.0 += 1
        }
        
        self.units.append(unitInfo)
        self.numActiveUnits += 1
        return { w in
            try w.addToOutputCorpus(unitInfo.unit!)
        }
    }
}

extension FuzzerInfo.Corpus {
    func updateScoresAndWeights() {
        coverageScore = 0
        for (u, idx) in zip(units, units.indices) {
            // the score is:
            // the sum of the score of each feature that this unit is the best one for
            // but it could be many other things, how do I know which one is best?
            units[idx].coverageScore = 0
            for f in (u.initiallyUniqueFeatures + u.initiallyReplacingBestUnitForFeatures) {
                if allFeatures[f]?.2 == .normal(idx) {
                    units[idx].coverageScore += f.score
                    coverageScore += f.score
                }
            }
        }
        for (u, idx) in zip(units, units.indices) {
            if u.unit != nil, u.coverageScore == 0 {
                print("DELETE") // FIXME: push this to World type in an effect return value
                units[idx].unit = nil
                numActiveUnits -= 1
            }
            
        }
        cumulativeWeights = units.enumerated().scan(0, { (weight, next) in
            let (_, unit) = next
            return weight + UInt64(unit.coverageScore)
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
        if favoredUnit != nil, r.positiveInt(4) == 0 {
            return .favored
        } else if units.isEmpty {
            return .favored
        } else {
            let x = r.weightedPickIndex(cumulativeWeights: cumulativeWeights)
            return .normal(x)
        }
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
