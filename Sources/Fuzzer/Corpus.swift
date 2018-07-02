
import Darwin

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
            let unit: T
            var coverageScore: Double
            let features: [Feature]
        }

        var units: [UnitInfo] = []
        var cumulativeWeights: [Double] = []
        var coverageScore: Double = 0
        var smallestUnitComplexityForFeature: [Feature.Reduced: Double] = [:]
        
        var favoredUnit: UnitInfo? = nil
        
        let coverageScoreThreshold = 0.5
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

        for f in unitInfo.features {
            let reduced = f.reduced
            
            let complexity = smallestUnitComplexityForFeature[reduced]
            if complexity == nil || unitInfo.unit.complexity() < complexity! {
                smallestUnitComplexityForFeature[reduced] = unitInfo.unit.complexity()
            }
        }
        self.units.append(unitInfo)
        return { w in
            try w.addToOutputCorpus(unitInfo.unit)
        }
    }
}

extension FuzzerInfo.Corpus {
    
    private func complexityRatio(simplest: Double, other: Double) -> Double {
        return { $0 * $0 }(simplest / other)
    }
    
    func updateScoresAndWeights() {
        coverageScore = 0
        
        var sumComplexityRatios: [Feature.Reduced: Double] = [:]
        
        for (u, idx) in zip(units, units.indices) {
            
            units[idx].coverageScore = 0
            // the score is:
            // The weighted sum of the scores of this units' features.
            // The weight is given by this set of equations:
            // 1) for feature f1, the sum of the f1-score of each unit is equal to f1.score
            // 2) given uf (the minimal unit for f1) and u2, the f1-score of u2 is equal to uf.c/u2.c * uf.f1-score
            //      that is: more complex units get fewer points per feature
            //    e.g. given: uf.c=1 ; u2.c=10 ; f1.score = 22
            //         we find: uf.f1-score = 20 ; u2.f1-score = 2
            //         f1.score = 22 = uf.f1-score + u2.f1-score
            //         u2.f1-score = uf.c/u2.c * uf.f1-score = 1/10 * 20 = 2
            for f in u.features {
                // TODO: implement globally-correct method
                //       maybe I won't need allFeatures.count anymore
                //       I will probably need to make Feature extra fast to compare/hash
                //       But first implement the dumb solution
                
                let simplestComplexity = smallestUnitComplexityForFeature[f.reduced]!
                let ratio = complexityRatio(simplest: simplestComplexity, other: u.unit.complexity())
                sumComplexityRatios[f.reduced, default: 0.0] += ratio
            }
        }
        for (u, idx) in zip(units, units.indices) {
            for f in u.features {
                let simplestComplexity = smallestUnitComplexityForFeature[f.reduced]!
                let sumRatios = sumComplexityRatios[f.reduced]!
                let baseScore = f.score / sumRatios
                let ratio = complexityRatio(simplest: simplestComplexity, other: u.unit.complexity())
                let score = baseScore * ratio
                units[idx].coverageScore += score
                coverageScore += score
            }
        }
        let prevCount = units.count
        units.removeAll { u in
            // TODO: use both the size of the corpus and the coverageScoreThreshold to determine whether to delete the feature
            return u.coverageScore <= coverageScoreThreshold
                && u.features.allSatisfy { smallestUnitComplexityForFeature[$0.reduced]! != u.unit.complexity() }
        }
        if prevCount - units.count != 0 {
            print("DELETE \(prevCount - units.count)")
        }
        cumulativeWeights = units.enumerated().scan(0.0, { (weight, next) in
            let (_, unit) = next
            return weight + unit.coverageScore
        })
    }
    
    func chooseUnitIdxToMutate(_ r: inout Rand) -> CorpusIndex {
        if favoredUnit != nil, r.bool(odds: 0.25) {
            return .favored
        } else if units.isEmpty {
            return .favored
        } else {
            let x = r.weightedRandomElement(cumulativeWeights: cumulativeWeights, minimum: 0)
            return .normal(x)
        }
    }

    func deleteUnit(_ idx: CorpusIndex) -> (inout World) throws -> Void {
        guard case .normal(let idx) = idx else {
            fatalError("Cannot delete special corpus unit.")
        }
        let oldUnit = units[idx].unit
        units.remove(at: idx)
        return { w in
            try w.removeFromOutputCorpus(oldUnit)
        }
    }
}
