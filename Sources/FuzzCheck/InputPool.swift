
/**
 The index for all FuzzerState.InputPool types.
 
 It points either to a regular element of the pool or to a “favored” element.
 */
enum InputPoolIndex: Equatable, Hashable {
    case normal(Int)
    case favored
}

extension FuzzerState {
    
    /**
     A `InputPool` is a collection of test inputs along with some of their
     analysis results.
     
     Each input in the `InputPool` is given a weight based on multiple factors
     (e.g. its features and its complexity). This weight determines the
     probability of being selected by the `randomIndex` method.
     
     The pool can also contain a “favored” input, which cannot be deleted and has
     a consistently high probability of being selected by `randomIndex`.
     
     Finally, the pool keeps track of the complexity of the simplest input that
     triggered each feature. It is used to filter out uninteresting inputs and
     to compute the score of each input.
     
     an inputPool can also have an alternate representation maintained by the
     Fuzzer’s world. For example, we could mirror the content of the pool in a
     folder in the file system. For that reason, some methods return a closure
     `(inout World) -> Void` that describes the action needed to maintain
     consistency between the pool and the world.
    */
    final class InputPool {
        
        /**
         Represents an input in the pool along with its initial analysis and
         its score in the input pool.
         */
        struct Element {
            let input: Input
            /// The complexity of the input
            let complexity: Double
            /// The features triggered by feeding the input to the test function
            let features: [Sensor.Feature]
            
            /**
             The relative score of the input in the pool.
             
             It depends on the other properties of InputPool.Element and the global
             state of the pool.
             
             It is not always set at initialization time and is not updated automatically
             after changes to the pool, so it should be kept in sync manually.
             */
            var score: Double
            
            // Is only used because `collection.removeAt(indices:)` is not
            // implemented in the stdlib and it's not worth reimplementing here
            var flaggedForDeletion: Bool
        
            init(input: Input, complexity: Double, features: [Sensor.Feature]) {
                self.input = input
                self.complexity = complexity
                self.features = features
                self.score = -1 // uninitialized
                self.flaggedForDeletion = false
            }
        }

        /// The main content of the pool
        var inputs: [Element] = []
        /// The favored input of the pool (optional)
        var favoredInput: Element? = nil
        
        /**
         `cumulativeWeights[idx]` is the sum of all the weights of the elements
         in `inputs[...idx]`.
         
         The weight of an input is an estimation of its relative importance
         compared to the other inputs in the pool.
        */
        var cumulativeWeights: [Double] = []
        
        /**
         The global score of all inputs in the pool. It should always be equal
         to the sum of each input’s score.
        */
        var score: Double = 0
        
        /**
         A dictionary that keeps track of the complexity of the simplest input that
         triggered each feature.
         
         Every feature that has ever been recorded by the fuzzer should be in this dictionary.
        */
        var smallestInputComplexityForFeature: [Sensor.Feature: Double] = [:]
    }
}

extension FuzzerState.InputPool {
    /**
     Access an input in the pool. It will crash if the index is invalid or
     if it is used to modify the favored input.
    */
    subscript(idx: InputPoolIndex) -> Element {
        get {
            switch idx {
            case .normal(let idx):
                return inputs[idx]
            case .favored:
                return favoredInput!
            }
        }
        set {
            switch idx {
            case .normal(let idx):
                inputs[idx] = newValue
            case .favored:
                fatalError("Cannot assign new input info to favoredInput")
            }
        }
    }
}

extension FuzzerState.InputPool {
    
    /**
     Add the input to the input pool. Update the score and weight of each input
     accordingly. This might result in other inputs being removed from the pool.
     
     - Complexity: Proportional to the sum of `inputs[i].features.count` for each `i` in
     `inputs.indices` (i.e. expensive)
     - Returns: The mutating function to apply to the World to keep it in sync with the pool
    */
    func add(_ inputInfo: Element) -> (inout World) throws -> Void {

        for f in inputInfo.features {
            let complexity = smallestInputComplexityForFeature[f]
            if complexity == nil || inputInfo.complexity < complexity! {
                smallestInputComplexityForFeature[f] = inputInfo.complexity
            }
        }
        inputs.append(inputInfo)
        let worldUpdate1 = updateCoverageScores()
        cumulativeWeights = inputs.scan(0.0) { $0 + $1.score }

        return { w in
            try worldUpdate1(&w)
            try w.addToOutputCorpus(inputInfo.input)
        }
    }
}

extension FuzzerState.InputPool {
    
    /**
     Update the score of every input in the pool
     - Complexity: Proportional to the sum of `inputs[i].features.count` for each `i` in
       `inputs.indices` (i.e. expensive)
     */
    func updateCoverageScores() -> (inout World) throws -> Void {
        /*
         NOTE: the logic for computing the scores will probably change, but here
         is an explanation of the current behavior.
         
         The main ideas are:
         1. Each feature has a score that is split among all inputs containing
         that feature. Because simpler inputs are considered better, they receive a
         larger share of the feature score.
         2. an input's score is the sum of the scores associated with
         each of its features
         
         Example:
         The pool contains three inputs: u1, u2, u3, which have triggered these features:
         - u1: f1 f2 f3
         - u2:    f2 f3
         - u3:    f2    f4
         To keep it simple, let's assume that all features (f1, f2, f3. f4) have the same
         score of 1.
         Finally, we need to know the inputs' complexities:
         - u1: 10.0
         - u2: 5.0
         - u3: 5.0
         The final scores of the inputs will be:
         - u1: 1.31
         - u2: 1.24
         - u3: 1.44
         
         Let's first split the score of the feature f2 between u1, u2, and u3.
         
         (Notation: the share of an input `u`'s score given by a feature `fy`
         is written `u.fy_score`)
         
         We need to satisfy these conditions:
         1. u1.f2_score + u2.f2_score + u3.f2_score == f2.score (== 2)
         2. u1.f2_score < u3.f2_score (because u3 is a simpler, better input than u1)
         3. u2.f2_score == u3.f2_score (because u2 and u3 have the same complexity)
         4. u3.f2_score == u3.f2_score (obviously)
         
         There are many possible solutions to this system of equation, so we need to choose
         a specific ratio between u1.f1_score and u3.f1_score. I chose to use the squared ratio
         of the complexities of u1 and u3 (why? because I had to choose something and lack the
         empirical evidence needed to make an informed choice).
         So the equations are, more specifically:
         1. u1.f2_score + u2.f2_score + u3.f2_score == f2.score (== 1)
         2. u1.f2_score = (u3.complexity / u1.complexity)^2 * u3.f2_score
         3. u2.f2_score = (u3.complexity / u2.complexity)^2 * u3.f2_score
         4. u3.f2_score = (u3.complexity / u3.complexity)^2 * u3.f2_score
         
         We replace the terms in (1) with (2) and (3), abbreviating (u3.complexity / ux.complexity)^2 by ratio(ux)
         1. ratio(u1) * u3.f2_score + ratio(u2) * u3.f2_score + ratio(u3) * u3.f2_score = f2.score
        
         which can be simplified to:
         1. (ratio(u1) + ratio(u2) + ratio(u3)) * u3.f2_score = f2.score
         => u3.f2_score = f2.score / (ratio(u1) + ratio(u2) + ratio(u3))     [ref: #LHBasKGXc]
         which allows us to compute an unknown of the equation, finally!
         => u3.f2_score = 1.0 / (0.25 + 1.0 + 1.0) = 0.44

         the remaining scores can now be computed:
         2. u1.f2_score = ratio(u1) * u3.f2_score = (5.0 / 10.0)^2 * 0.44 = 0.11
         3. u2.f2_score = ratio(u2) * u3.f2_score = (5.0 / 5.0)^2 * 0.44 = 0.44
        
         It all checks out:
         1. u1.f2_score + u2.f2_score + u3.f2_score == 0.11 + 0.44 + 0.44 = 1.0 = f2.score
         
         Repeat this procedure with the other features to find the total score of each unit.
         
         So, in order to compute the score of each unit, we need to sum the complexity ratio between
         a particular unit and all other units (see: #LHBasKGXc). We decide that this “particular unit”
         is the simplest unit containing the feature (as we already keep track of its complexity in
         `smallestInputComplexityForFeature`).
         
         This is what the code below does!
         
         Except not really! There is an exception.
         
         If an input is not the simplest one to contain any particular feature, we delete it from
         the pool, to avoid pool bloat. Maybe in the future we should use inputs' scores to decide
         whether to delete them from the pool, but that would be more complicated.
         */
        
        func complexityRatio(simplest: Double, other: Double) -> Double {
            // the square of the ratio of complexities
            return { $0 * $0 }(simplest / other)
        }
        
        // I am sure this could be much faster.

        // First iterate over all inputs and features to initialize sumComplexityRatios
        var sumComplexityRatios: [Sensor.Feature: Double] = [:] // see: #LHBasKGXc
        for (input, idx) in zip(inputs, inputs.indices) {
            inputs[idx].flaggedForDeletion = true
            inputs[idx].score = 0
            for f in input.features {
                let simplestComplexity = smallestInputComplexityForFeature[f]!
                let ratio = complexityRatio(simplest: simplestComplexity, other: input.complexity)
                precondition(ratio <= 1)
                if ratio == 1 { inputs[idx].flaggedForDeletion = false }
            }
            guard inputs[idx].flaggedForDeletion == false else {
                continue
            }
            for f in input.features {
                let simplestComplexity = smallestInputComplexityForFeature[f]!
                let ratio = complexityRatio(simplest: simplestComplexity, other: input.complexity)
                sumComplexityRatios[f, default: 0.0] += ratio
            }
        }
        
        // Then use sumComplexityRatios to find the score of each feature for each unit and sum all the things
        for (input, idx) in zip(inputs, inputs.indices) where input.flaggedForDeletion == false {
            for f in input.features {
                let simplestComplexity = smallestInputComplexityForFeature[f]!
                let sumRatios = sumComplexityRatios[f]!
                let baseScore = f.score / sumRatios
                let ratio = complexityRatio(simplest: simplestComplexity, other: input.complexity)
                let score = baseScore * ratio
                inputs[idx].score += score
            }
        }
        
        // remove inputs that don't deserve to be in the pool anymore
        let inputsToDelete = inputs.filter { $0.flaggedForDeletion }.map { $0.input }
        let worldUpdate: (inout World) throws -> Void = { [inputsToDelete] w in
            for u in inputsToDelete {
                try w.removeFromOutputCorpus(u)
            }
            if !inputsToDelete.isEmpty {
                print("DELETE \(inputsToDelete.count)")
            }
        }

        inputs.removeAll { $0.flaggedForDeletion }

        score = inputs.reduce(0) { $0 + $1.score }
        
        return worldUpdate
    }
    
    
    func randomIndex(_ r: inout Rand) -> InputPoolIndex {
        // maybe the odd of choosing the favoredInput should decrease as time goes on
        if favoredInput != nil, r.bool(odds: 0.25) {
            return .favored
        } else if inputs.isEmpty {
            return .favored
        } else {
            let x = r.weightedRandomIndex(cumulativeWeights: cumulativeWeights, minimum: 0)
            return .normal(x)
        }
    }
}
