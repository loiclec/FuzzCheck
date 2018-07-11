
/**
 The index for all FuzzerState.UnitPool types.
 
 It points either to a regular element of the pool or to a “favored” element.
 */
enum UnitPoolIndex: Equatable, Hashable {
    case normal(Int)
    case favored
}

extension FuzzerState {
    
    /**
     A `UnitPool` is a collection of test units along with some of their
     code coverage analysis results.
     
     Each unit in the `UnitPool` is given a weight based on multiple factors
     (e.g. its code coverage features and its complexity). This weight
     determines the probability of being selected by the `randomIndex` method.
     
     The pool can also contain a “favored” unit, which cannot be deleted and has
     a consistently high probability of being selected by `randomIndex`.
     
     Finally, the pool keeps track of the complexity of the simplest unit that
     triggered each code coverage feature. It is used to filter out uninteresting
     units and to compute the code coverage score of each unit.
     
     A UnitPool can also have an alternate representation maintained by the
     Fuzzer’s world. For example, we could mirror the content of the pool in a
     folder in the file system. For that reason, some methods return a closure
     `(inout World) -> Void` that describes the action needed to maintain
     consistency between the pool and the world.
    */
    final class UnitPool {
        
        /**
         Represents a unit in the pool along with its initial code coverage analysis
         and its code coverage score in the unit pool.
         */
        struct UnitInfo {
            let unit: Unit
            /// The complexity of the unit
            let complexity: Double
            /// The code coverage features triggered by feeding the unit to the test function
            let features: [Sensor.Feature]
            
            /**
             The relative coverage score of the unit in the pool.
             
             It depends on the other properties of UnitInfo and the global
             state of the pool.
             
             It is not always set at initialization time and is not updated automatically
             after changes to the pool, so it should be kept in sync manually.
             */
            var coverageScore: Double
            
            // Is only used because `collection.removeAt(indices:)` is not
            // implemented in the stdlib and it's not worth reimplementing here
            var flaggedForDeletion: Bool
        
            init(unit: Unit, complexity: Double, features: [Sensor.Feature]) {
                self.unit = unit
                self.complexity = complexity
                self.features = features
                self.coverageScore = -1 // uninitialized
                self.flaggedForDeletion = false
            }
        }

        /// The main content of the pool
        var units: [UnitInfo] = []
        /// The favored unit of the pool (optional)
        var favoredUnit: UnitInfo? = nil
        
        /**
         `cumulativeWeights[idx]` is the sum of all the weights of the elements
         in `units[...idx]`.
         
         The weight of a unit is an estimation of its relative importance
         compared to the other units in the pool.
        */
        var cumulativeWeights: [Double] = []
        
        /**
         The global coverage score of all units in the pool. It should always be equal
         to the sum of each unit’s coverage score.
        */
        var coverageScore: Double = 0
        
        /**
         A dictionary that keeps track of the complexity of the simplest unit that
         triggered each code coverage feature.
         
         Every feature that has ever been recorded by the fuzzer should be in this dictionary.
        */
        var smallestUnitComplexityForFeature: [Sensor.Feature: Double] = [:]
    }
}

extension FuzzerState.UnitPool {
    /**
     Access a unit in the pool. It will crash if the index is invalid or
     if it is used to modify the favored unit.
    */
    subscript(idx: UnitPoolIndex) -> UnitInfo {
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

extension FuzzerState.UnitPool {
    
    /**
     Add the unit to the unit pool. Update the coverage score and weight of each unit
     accordingly. This might result in other units being removed from the pool.
     
     - Complexity: Proportional to the sum of `units[i].features.count` for each `i` in
     `units.indices` (i.e. expensive)
     - Returns: The mutating function to apply to the World to keep it in sync with the pool
    */
    func add(_ unitInfo: UnitInfo) -> (inout World) throws -> Void {

        for f in unitInfo.features {
            let complexity = smallestUnitComplexityForFeature[f]
            if complexity == nil || unitInfo.complexity < complexity! {
                smallestUnitComplexityForFeature[f] = unitInfo.complexity
            }
        }
        units.append(unitInfo)
        let worldUpdate1 = updateCoverageScores()
        cumulativeWeights = units.scan(0.0) { $0 + $1.coverageScore }

        return { w in
            try worldUpdate1(&w)
            try w.addToOutputCorpus(unitInfo.unit)
        }
    }
}

extension FuzzerState.UnitPool {
    
    /**
     Update the coverage score of every unit in the pool
     - Complexity: Proportional to the sum of `units[i].features.count` for each `i` in
       `units.indices` (i.e. expensive)
     */
    func updateCoverageScores() -> (inout World) throws -> Void {
        /*
         NOTE: the logic for computing the coverage scores will probably change, but here
         is an explanation of the current behavior.
         
         The main ideaa are:
         1. Each feature has a coverage score that is split among all units containing
         that feature. Because simpler units are considered better, they receive a
         larger share of the feature score.
         2. A unit's coverage score is the sum of the coverage scores associated with
         each of its features
         
         Example:
         The pool contains three units: u1, u2, u3, which have triggered these features:
         - u1: f1 f2 f3
         - u2:    f2 f3
         - u3: f1 f2    f4
         To keep it simple, let's assume that all features (f1, f2, f3. f4) have the same
         score of 2.
         Finally, we need to know the units' complexities:
         - u1: 10.0
         - u2: 5.0
         - u3: 5.0
         
         The coverage scores of the units are:
         - 
         
         Let's first split the coverage score of the feature f2 between u1, u2, and u3.
         
         (Notation: the share of a unit `u`'s coverage score given by a feature `fy`
         is written `u.fy_score`)
         
         We need to satisfy these conditions:
         1. u1.f2_score + u2.f2_score + u3.f2_score == f2.score (== 2)
         2. u1.f2_score < u3.f2_score (because u3 is a simpler, better unit than u1)
         3. u2.f2_score == u3.f2_score (because u2 and u3 have the same complexity)
         
         There are many possible solutions to this system of equation, so we need to choose
         a specific ratio between u1.f1_score and u3.f1_score. I chose to use the squared ratio
         of u1 and u3
        */
        func complexityRatio(simplest: Double, other: Double) -> Double {
            // the square of the ratio of complexities
            return { $0 * $0 }(simplest / other)
        }
        
        coverageScore = 0
        var sumComplexityRatios: [Sensor.Feature: Double] = [:]
        for (u, idx) in zip(units, units.indices) {
            units[idx].flaggedForDeletion = true
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
                let simplestComplexity = smallestUnitComplexityForFeature[f]!
                let ratio = complexityRatio(simplest: simplestComplexity, other: u.complexity)
                precondition(ratio <= 1)
                if ratio == 1 { units[idx].flaggedForDeletion = false }
            }
            guard units[idx].flaggedForDeletion == false else {
                continue
            }
            for f in u.features {
                let simplestComplexity = smallestUnitComplexityForFeature[f]!
                let ratio = complexityRatio(simplest: simplestComplexity, other: u.complexity)
                sumComplexityRatios[f, default: 0.0] += ratio
            }
        }
        for (u, idx) in zip(units, units.indices) where u.flaggedForDeletion == false {
            for f in u.features {
                let simplestComplexity = smallestUnitComplexityForFeature[f]!
                let sumRatios = sumComplexityRatios[f]!
                let baseScore = f.score / sumRatios
                let ratio = complexityRatio(simplest: simplestComplexity, other: u.complexity)
                let score = baseScore * ratio
                units[idx].coverageScore += score
                coverageScore += score
            }
        }
        let unitsToDelete = units.filter { $0.flaggedForDeletion }.map { $0.unit }
        let worldUpdate: (inout World) throws -> Void = { [unitsToDelete] w in
            for u in unitsToDelete {
                try w.removeFromOutputCorpus(u)
            }
            if !unitsToDelete.isEmpty {
                print("DELETE \(unitsToDelete.count)")
            }
        }
        
        units.removeAll { $0.flaggedForDeletion }
        return worldUpdate
    }
    
    /**
     Update the coverage score of each unit in the pool,
    */
    func updateScoresAndWeights() {
        
        func complexityRatio(simplest: Double, other: Double) -> Double {
            // the square of the ratio of complexities
            return { $0 * $0 }(simplest / other)
        }
        
        coverageScore = 0
        var sumComplexityRatios: [Sensor.Feature: Double] = [:]
        for (u, idx) in zip(units, units.indices) {
            units[idx].flaggedForDeletion = true
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
                let simplestComplexity = smallestUnitComplexityForFeature[f]!
                let ratio = complexityRatio(simplest: simplestComplexity, other: u.complexity)
                precondition(ratio <= 1)
                if ratio == 1 { units[idx].flaggedForDeletion = false }
            }
            guard units[idx].flaggedForDeletion == false else {
                continue
            }
            for f in u.features {
                let simplestComplexity = smallestUnitComplexityForFeature[f]!
                let ratio = complexityRatio(simplest: simplestComplexity, other: u.complexity)
                sumComplexityRatios[f, default: 0.0] += ratio
            }
        }
        for (u, idx) in zip(units, units.indices) where u.flaggedForDeletion == false {
            for f in u.features {
                let simplestComplexity = smallestUnitComplexityForFeature[f]!
                let sumRatios = sumComplexityRatios[f]!
                let baseScore = f.score / sumRatios
                let ratio = complexityRatio(simplest: simplestComplexity, other: u.complexity)
                let score = baseScore * ratio
                units[idx].coverageScore += score
                coverageScore += score
            }
        }
        let prevCount = units.count
        units.removeAll { $0.flaggedForDeletion }
        if prevCount - units.count != 0 {
            print("DELETE \(prevCount - units.count)")
        }
        cumulativeWeights = units.scan(0.0) { $0 + $1.coverageScore }
    }
    
    func randomIndex(_ r: inout Rand) -> UnitPoolIndex {
        if favoredUnit != nil, r.bool(odds: 0.25) {
            return .favored
        } else if units.isEmpty {
            return .favored
        } else {
            let x = r.weightedRandomElement(cumulativeWeights: cumulativeWeights, minimum: 0)
            return .normal(x)
        }
    }

    func deleteUnit(_ idx: UnitPoolIndex) -> (inout World) throws -> Void {
        guard case .normal(let idx) = idx else {
            fatalError("Cannot delete special pool unit.")
        }
        let oldUnit = units[idx].unit
        units.remove(at: idx)
        return { w in
            try w.removeFromOutputCorpus(oldUnit)
        }
    }
}
