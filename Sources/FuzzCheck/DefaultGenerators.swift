
public struct IntegerFuzzingMutators <T: FixedWidthInteger & RandomInitializable> : FuzzUnitMutators {
    public typealias Unit = T
    
    public enum Mutator {
        case nudge
        case random
        case special
    }
    
    public func mutate(_ unit: inout Unit, with mutator: Mutator, _ rand: inout Rand) -> Bool {
        switch mutator {
        case .nudge:
            return nudge(&unit, &rand)
        case .random:
            return random(&unit, &rand)
        case .special:
            return special(&unit, &rand)
        }
    }
    
    func nudge(_ x: inout Unit, _ r: inout Rand) -> Bool {
        let nudge = Unit(r.next(upperBound: 10 as UInt))
        let op: (Unit, Unit) -> Unit = Bool.random(using: &r) ? (&-) : (&+)
        x = op(x, nudge)
        return true
    }
    
    func random(_ x: inout Unit, _ r: inout Rand) -> Bool {
        x = T.random(using: &r)
        return true
    }
    
    func special(_ x: inout Unit, _ r: inout Rand) -> Bool {
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
                _ = mutate(&x, &r)
            }
            return x
        }
    }
}

struct IntegerFuzzing <T: FixedWidthInteger & RandomInitializable> : FuzzUnit {
    
    let mutators = IntegerFuzzingMutators<T>()
    let baseUnit = 0 as T
    
    func mutate(_ x: inout T, _ r: inout Rand) -> Bool {
        return mutators.mutate(&x, &r)
    }

    static func hash(of unit: T) -> Int {
        return unit.hashValue
    }
    static func complexity(of: T) -> Double {
        return Double(T.bitWidth) / 8
    }
}

extension FixedWidthInteger where Self: UnsignedInteger {
    public func complexity() -> Double {
        return 1.0
    }
    public func hash() -> Int {
        return self.hashValue
    }
}

public struct ArrayMutators <M: FuzzUnitMutators> : FuzzUnitMutators {
    public typealias Unit = Array<M.Unit>
    
    public let initializeElement: (inout Rand) -> M.Unit
    public let elementMutators: M
    
    public init(initializeElement: @escaping (inout Rand) -> M.Unit, elementMutators: M) {
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
    
    public func mutate(_ unit: inout Array<M.Unit>, with mutator: ArrayMutators<M>.Mutator, _ rand: inout Rand) -> Bool {
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
    
    func appendNew(_ x: inout Unit, _ r: inout Rand) -> Bool {
        x.append(initializeElement(&r))
        return true
    }
    
    func appendRecycled(_ x: inout Unit, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        let y = x.randomElement(using: &r)!
        x.append(y)
        return true
    }
    
    func insertNew(_ x: inout Unit, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        let i = x.indices.randomElement(using: &r)!
        x.insert(initializeElement(&r), at: i)
        return true
    }
    
    func insertRecycled(_ x: inout Unit, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        let y = x.randomElement(using: &r)!
        let i = x.indices.randomElement(using: &r)!
        x.insert(y, at: i)
        return true
    }
    
    func removeLast(_ x: inout Unit, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        x.removeLast()
        return true
    }
    
    func removeFirst(_ x: inout Unit, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        x.removeFirst()
        return true
    }
    
    func removeRandom(_ x: inout Unit, _ r: inout Rand) -> Bool {
        guard !x.isEmpty else { return false }
        x.remove(at: x.indices.randomElement(using: &r)!)
        return true
    }
    
    func swap(_ x: inout Unit, _ r: inout Rand) -> Bool {
        
        guard x.count > 1 else { return false }
        let (i, j) = (x.indices.randomElement(using: &r)!, x.indices.randomElement(using: &r)!)
        x.swapAt(i, j)
        return i != j
    }
    
    func mutateElement(_ x: inout Unit, _ r: inout Rand) -> Bool {
        
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
