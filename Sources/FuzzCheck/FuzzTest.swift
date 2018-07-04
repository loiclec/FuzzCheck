
public protocol FuzzUnitGenerator {
    associatedtype Unit
    associatedtype Mut: Mutators where Mut.Mutated == Unit
    
    var mutators: Mut { get }
    var baseUnit: Unit { get }
    
    func initialUnits(_ r: inout Rand) -> [Unit]
}

public protocol FuzzUnit: Codable {
    func complexity() -> Double
    func hash() -> Int
}

public protocol Mutators {
    associatedtype Mutated: FuzzUnit
    associatedtype Mutator
    
    func mutate(_ unit: inout Mutated, with mutator: Mutator, _ rand: inout Rand) -> Bool
    
    var weightedMutators: [(Mutator, UInt)] { get }
}
extension Mutators {
    public func mutate(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        for _ in 0 ..< weightedMutators.count {
            let mutator = r.weightedRandomElement(from: weightedMutators, minimum: 0)
            if mutate(&x, with: mutator, &r) { return true }
        }
        return false
    }
}
