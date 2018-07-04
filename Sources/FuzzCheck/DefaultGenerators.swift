
public struct IntegerMutators <T: FixedWidthInteger & RandomInitializable & FuzzUnit> : Mutators {
    public typealias Mutated = T
    
    public enum Mutator {
        case nudge
        case random
        case special
    }
    
    public func mutate(_ unit: inout Mutated, with mutator: Mutator, _ rand: inout Rand) -> Bool {
        switch mutator {
        case .nudge:
            return nudge(&unit, &rand)
        case .random:
            return random(&unit, &rand)
        case .special:
            return special(&unit, &rand)
        }
    }
    
    func nudge(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        let nudge = Mutated(r.next(upperBound: 10 as UInt))
        let op: (Mutated, Mutated) -> Mutated = Bool.random(using: &r) ? (&-) : (&+)
        x = op(x, nudge)
        return true
    }
    
    func random(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        x = T.random(using: &r)
        return true
    }
    
    func special(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        let oldX = x
        switch r.next(upperBound: 3 as UInt) {
        case 0 : x = .min
        case 1 : x = .max
        case 2 : x = 0
        default: fatalError()
        }
        return x != oldX
    }
    
    public init() {}
    
    public let weightedMutators: [(Mutator, UInt)] = [
        (.special, 1),
        (.random, 11),
        (.nudge, 21),
    ]
}

extension FuzzUnitGenerator {
    public func initialUnits(_ r: inout Rand) -> [Unit] {
        return (0 ..< 10).map { i in
            var x = baseUnit
            for _ in 0 ..< (i * 10) {
                _ = mutators.mutate(&x, &r)
            }
            return x
        }
    }
}

struct IntegerGenerator <T: FixedWidthInteger & RandomInitializable & FuzzUnit> : FuzzUnitGenerator {
    let mutators = IntegerMutators<T>()
    let baseUnit = 0 as T
}

extension FixedWidthInteger where Self: UnsignedInteger {
    public func complexity() -> Double {
        return 1.0
    }
    public func hash() -> Int {
        return self.hashValue
    }
}

extension Array: FuzzUnit where Element: FuzzUnit {
    public func complexity() -> Double {
        return Double(1 + count)
    }
    
    public func hash() -> Int {
        var hasher = Hasher()
        for x in self {
            hasher.combine(x.hash())
        }
        return hasher.finalize()
    }
}

public struct ArrayMutators <M: Mutators> : Mutators {
    public typealias Mutated = Array<M.Mutated>
    
    public let initializeElement: (inout Rand) -> M.Mutated
    public let elementMutators: M
    
    public init(initializeElement: @escaping (inout Rand) -> M.Mutated, elementMutators: M) {
        self.initializeElement = initializeElement
        self.elementMutators = elementMutators
    }
    
    public enum Mutator {
        case appendNew
        case appendRecycled
        case insertNew
        case insertRecycled
        case mutateElement
        case swap
        case removeLast
        case removeRandom
    }
    
    public func mutate(_ unit: inout Array<M.Mutated>, with mutator: ArrayMutators<M>.Mutator, _ rand: inout Rand) -> Bool {
        switch mutator {
        case .appendNew:
            return appendNew(&unit, &rand)
        case .appendRecycled:
            return appendRecycled(&unit, &rand)
        case .insertNew:
            return insertNew(&unit, &rand)
        case .insertRecycled:
            return insertRecycled(&unit, &rand)
        case .mutateElement:
            return mutateElement(&unit, &rand)
        case .swap:
            return swap(&unit, &rand)
        case .removeLast:
            return removeLast(&unit, &rand)
        case .removeRandom:
            return removeRandom(&unit, &rand)
        }
    }
    
    func appendNew(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        x.append(initializeElement(&r))
        return true
    }
    
    func appendRecycled(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        let y = x.randomElement(using: &r)!
        x.append(y)
        return true
    }
    
    func insertNew(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        let i = x.indices.randomElement(using: &r)!
        x.insert(initializeElement(&r), at: i)
        return true
    }
    
    func insertRecycled(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        let y = x.randomElement(using: &r)!
        let i = x.indices.randomElement(using: &r)!
        x.insert(y, at: i)
        return true
    }
    
    func removeLast(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        x.removeLast()
        return true
    }
    
    func removeFirst(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        x.removeFirst()
        return true
    }
    
    func removeRandom(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        x.remove(at: x.indices.randomElement(using: &r)!)
        return true
    }
    
    func swap(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        
        guard x.count > 1 else { return false }
        let (i, j) = (x.indices.randomElement(using: &r)!, x.indices.randomElement(using: &r)!)
        x.swapAt(i, j)
        return i != j
    }
    
    func mutateElement(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        
        guard !x.isEmpty else { return false }
        let i = x.indices.randomElement(using: &r)!
        return elementMutators.mutate(&x[i], &r)
    }
    
    public let weightedMutators: [(Mutator, UInt)] = [
        (.appendNew, 40),
        (.appendRecycled, 80),
        (.insertNew, 120),
        (.insertRecycled, 160),
        (.mutateElement, 300),
        (.swap, 380),
        (.removeLast, 420),
        (.removeRandom, 460)
    ]
}
