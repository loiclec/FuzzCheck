
public protocol FuzzUnitGenerator {
    associatedtype Unit
    
    var baseUnit: Unit { get }
    func initialUnits(_ r: inout Rand) -> [Unit]
    
    func mutate(_ x: inout Unit, _ r: inout Rand) -> Bool
}

public protocol FuzzUnitProperties {
    associatedtype Unit
    static func complexity(of: Unit) -> Double
    static func hash(of: Unit) -> Int 
}

public protocol FuzzUnitMutators {
    associatedtype Mutated
    associatedtype Mutator
    
    func mutate(_ unit: inout Mutated, with mutator: Mutator, _ rand: inout Rand) -> Bool
    
    var weightedMutators: [(Mutator, UInt)] { get }
}
extension FuzzUnitMutators {
    public func mutate(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        for _ in 0 ..< weightedMutators.count {
            let mutator = r.weightedRandomElement(from: weightedMutators, minimum: 0)
            if mutate(&x, with: mutator, &r) { return true }
        }
        return false
    }
}
