
/// A protocol defining how to generate and mutate values of type Unit.
public protocol FuzzUnitGenerator {
    
    associatedtype Unit
    
    /**
     The simplest value of `Unit`.
     
     Having a perfect value for `baseUnit` is not essential to FuzzCheck.
     
     ## Examples
     - the empty array
     - the number 0
     - an arbitrary value if `Unit` doesn't have a “simplest” value
    */
    var baseUnit: Unit { get }
    
    /**
     Returns an array of initial units to fuzz-test.
     
     The elements of the array should be different from each other, and
     each one of them should be interesting in its own way.
     
     For example, one could be an empty array, another one could be a sorted array,
     one a small array and one a large array, etc.
     
     Having a perfect list of initial elements is not essential to FuzzCheck,
     but it can help it start working on the right foot.
     
     - Parameter rand: a source of randomness
    */
    func initialUnits(_ rand: inout Rand) -> [Unit]
    
    /**
     Mutate the given unit.
     
     FuzzCheck will call this method repeatedly in order to explore all the
     possible values of Unit. It is therefore important that it is implemented
     efficiently.
     
     It should be theoretically possible to mutate any arbitrary unit `u1` into any
     other arbitrary unit `u2` by calling `mutate` repeatedly.
     
     Moreover, the result of `mutate` should try to be “interesting” to FuzzCheck.
     That is, it should be likely to trigger new code paths when passed to the
     test function.
     
     A good approach to implement this method is to use a `FuzzUnitMutators`.
     
     ## Examples
     - append a random element to an array
     - mutate a random element in an array
     - subtract a small constant from an integer
     - change an integer to Int.min or Int.max or 0
     - replace a substring by a keyword relevant to the test function
     
     - Parameter unit: the unit to mutate
     - Parameter rand: a source of randomness
     - Returns: true iff the unit was actually mutated
    */
    func mutate(_ unit: inout Unit, _ rand: inout Rand) -> Bool
}

/**
 A protocol giving some information about values of type Unit, such as its complexity or hash.
 
 Unit itself is not required to conform to any protocol...:
- to allow multiple different implementations to coexist
- to allow fuzz-testing of non-nominal types
 */
public protocol FuzzUnitProperties {
    associatedtype Unit
    /**
     Returns the complexity of the given unit.
     
     FuzzCheck will prefer using units with a smaller complexity.
     
     - Important: The return value must be >= 0
     
     ## Examples
     - an array might have a complexity equal to the sum of complexities of its elements
     - an integer might have a complexity equal to the number of bytes used to represent it
     */
    static func complexity(of unit: Unit) -> Double
    
    /// - Returns: the hash value of the given unit
    static func hash(of unit: Unit) -> Int
}

/// Types conforming to this protocol contain all the necessary information
/// to fuzz-test values of the associated type Unit.
public protocol FuzzUnit: FuzzUnitGenerator, FuzzUnitProperties { }

/**
 A type providing a list of weighted mutators.
 
 The weight of a mutator determines how often it should be used relative to
 the other mutators in the list.
 */
public protocol FuzzUnitMutators {
    associatedtype Unit
    associatedtype Mutator

    /**
     Mutate the given unit using the given mutator and source of randomness.
     
     - Parameter unit: the unit to mutate
     - Parameter mutator: the mutator to use to mutate the unit
     - Parameter rand: a source of randomness
     - Returns: true iff the unit was actually mutated
    */
    func mutate(_ unit: inout Unit, with mutator: Mutator, _ rand: inout Rand) -> Bool
    
    /**
     A list of mutators and their associated weight.
     
     # IMPORTANT
     The second component of the tuples in the array is the sum of the previous weight
     and the weight of the mutator itself. For example, if we have three mutators
     `(m1, m2, m3)` with relative weight `(120, 5, 56)`. Then `weightedMutators`
     should return `[(m1, 120), (m2, 125), (m3, 181)]`.
    */
    var weightedMutators: [(Mutator, UInt)] { get }
}

extension FuzzUnitMutators {
    /**
     Choose a mutator from the list of weighted mutators and execute it on `unit`.
     
     - Parameter unit: the unit to mutate
     - Parameter mutator: the mutator to use to mutate the unit
     - Parameter rand: a source of randomness
     - Returns: true iff the unit was actually mutated
     */
    public func mutate(_ unit: inout Unit, _ rand: inout Rand) -> Bool {
        for _ in 0 ..< weightedMutators.count {
            let mutator = rand.weightedRandomElement(from: weightedMutators, minimum: 0)
            if mutate(&unit, with: mutator, &rand) { return true }
        }
        return false
    }
}
