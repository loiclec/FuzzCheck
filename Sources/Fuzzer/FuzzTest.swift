
public protocol FuzzUnit: Codable {
    func complexity() -> Complexity
    func hash() -> Int
}

public protocol Mutators {
    associatedtype Mutated: FuzzUnit
    associatedtype Mutator
    
    func mutate(_ unit: inout Mutated, with mutator: Mutator, _ rand: inout Rand) -> Bool
    
    var weightedMutators: [(Mutator, UInt64)] { get }
}
extension Mutators {
    public func mutate(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        for _ in 0 ..< weightedMutators.count {
            let mutator = r.arrayWeightedPick(fromSmall: weightedMutators)
            if mutate(&x, with: mutator, &r) { return true }
        }
        return false
    }
}

public struct IntWrapper: FuzzUnit, CustomStringConvertible {
    public var x: Int
    
    public init(x: Int) { self.x = x }

    public func complexity() -> Complexity {
        let c = self.x <= 0 ? Double.greatestFiniteMagnitude : (200.0 + (100.0 / Double(self.x))) 
        return Complexity(c)
    }
    
    public func hash() -> Int {
        return x
    }

    public var description: String { return x.description }
}

public struct IntWrapperMutators: Mutators {
    public typealias Mutated = IntWrapper
    
    public enum Mutator {
        case nudge
    }
    
    public init() {}

    public func mutate(_ unit: inout IntWrapper, with mutator: IntWrapperMutators.Mutator, _ rand: inout Rand) -> Bool {
        switch mutator {
        case .nudge:
            unit.x = unit.x &+ rand.int(inside: -11 ..< 11)
            return true
        }
    }
    
    public let weightedMutators: [(IntWrapperMutators.Mutator, UInt64)] = [
        (.nudge, 1)
    ]
}

extension FixedWidthInteger where Self: UnsignedInteger {
    public func complexity() -> Complexity {
        return 1.0
    }
    public func hash() -> Int {
        return self.hashValue
    }
}

public struct UnsignedIntegerMutators <I: FixedWidthInteger & UnsignedInteger & FuzzUnit> : Mutators {
    public typealias Mutated = I
    
    public enum Mutator {
        case nudge
        case random
        case special
    }
    
    public func mutate(_ unit: inout I, with mutator: UnsignedIntegerMutators<I>.Mutator, _ rand: inout Rand) -> Bool {
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
        let nudge = r.integer(inside: (0 as I) ..< (10 as I))
        let op: (I, I) -> I = r.bool() ? (&-) : (&+)
        x = op(x, nudge)
        return true
    }
    
    func random(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        x = r.next()
        return true
    }
    
    func special(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        let oldX = x
        x = r.bool() ? I.min : I.max
        return x != oldX
    }
    
    public init() {}
    
    public let weightedMutators: [(Mutator, UInt64)] = [
        (.special, 1),
        (.random, 11),
        (.nudge, 21),
    ]
}

extension Array: FuzzUnit where Element: FuzzUnit {
    public func complexity() -> Complexity {
        return Complexity(Double(1 + count))
    }
    
    public func hash() -> Int {
        return self.reduce(1.hashValue) { ($0 &* 65371) ^ $1.hash() }
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
        let y = r.pick(from: x)
        x.append(y)
        return true
    }
    
    func appendRepeatedNew(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        
        guard !x.isEmpty else { return false }
        let y = initializeElement(&r)
        let count = r.positiveInt(x.count) + 1 // TODO: don't use uniform distribution, favor lower values
        x += repeatElement(y, count: count)
        return true
    }
    
    func insertNew(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        
        guard !x.isEmpty else { return false }
        let i = r.int(inside: x.indices)
        x.insert(initializeElement(&r), at: i)
        return true
    }
    
    func insertRecycled(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        
        guard !x.isEmpty else { return false }
        let y = r.pick(from: x)
        let i = r.int(inside: x.indices)
        x.insert(y, at: i)
        return true
    }
    
    func insertRepeatedNew(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        
        guard !x.isEmpty else { return false }
        let y = initializeElement(&r)
        let count = r.positiveInt(x.count) + 1 // TODO: don't use uniform distribution, favor lower values
        let i = r.int(inside: x.indices)
        x.insert(contentsOf: repeatElement(y, count: count), at: i)
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
    
    func removeNFirst(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        
        guard !x.isEmpty else { return false }
        let count = r.positiveInt(x.count) + 1  // TODO: don't use uniform distribution, favor lower values
        x.removeFirst(count)
        return true
    }
    
    func removeRandom(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        
        guard !x.isEmpty else { return false }
        x.remove(at: r.positiveInt(x.endIndex))
        return true
    }
    
    func swap(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        
        guard x.count > 1 else { return false }
        let (i, j) = (r.int(inside: x.indices), r.int(inside: x.indices))
        x.swapAt(i, j)
        return i != j
    }
    
    func removeSubrange(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        
        guard !x.isEmpty else { return false }
        let start = r.int(inside: x.indices)
        let end = r.int(inside: start ..< x.endIndex)
        x.removeSubrange(start ..< end)
        return start != end
    }
    
    func moveSubrange(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        
        guard x.count > 1 else { return false }
        let sourceStart = r.int(inside: x.indices)
        guard sourceStart != (x.endIndex-1) else { return false }
        let sourceEnd = r.int(inside: sourceStart ..< x.endIndex)
        
        let destStart = r.int(inside: x.indices)
        let destEnd = destStart + sourceStart.distance(to: sourceEnd)
        x.replaceSubrange(destStart ..< destEnd, with: x[sourceStart ..< sourceEnd])
        
        return sourceStart != sourceEnd && sourceStart != destStart
    }
    
    func mutateElement(_ x: inout Mutated, _ r: inout Rand) -> Bool {
        
        guard !x.isEmpty else { return false }
        let i = r.int(inside: x.indices)
        return elementMutators.mutate(&x[i], &r)
    }
    
    func mutateSubrange(_ x: inout Array<M.Mutated>, _ r: inout Rand) -> Bool {
        
        guard !x.isEmpty else { return false }
        let start = r.int(inside: x.indices)
        let end = r.int(inside: start ..< x.endIndex) // TODO: do no use uniform distribution
        var res = false
        for i in start ..< end {
            res = res || elementMutators.mutate(&x[i], &r)
        }
        return res
    }
    
    public func replaceCompletely(_ x: inout Array<M.Mutated>, _ r: inout Rand) -> Bool {
        x.removeAll()
        let count = r.positiveInt(256)
        for _ in 0 ..< count {
            x.append(initializeElement(&r))
        }
        return true
    }
    
    public let weightedMutators: [(Mutator, UInt64)] = {
        let haveRepeatingVariant: [(Mutator, UInt64)] = [
            (.appendNew, 40),
            (.appendRecycled, 80),
            (.insertNew, 120),
            (.insertRecycled, 160),
            (.mutateElement, 300),
            (.swap, 380),
            (.removeLast, 420),
            (.removeRandom, 460)
        ]
        /*
        let repeatingVariants = haveRepeatingVariant.map { (m: (Mutator<Mutated>, UInt64)) -> (Mutator<Mutated>, UInt64) in
            let rm = ArrayMutators.repeatMutator(m.0, count: { (r: inout Rand, max: Int) -> Int in
                return r.positiveInt(max+1)
            })
            return (rm, m.1 / 4)
        }*//*
        let others: [(Mutator<Mutated>, UInt64)] = [
            (self.appendRepeatedNew, 10),
            (self.insertRepeatedNew, 10),
            (self.moveSubrange, 10),
            (self.removeSubrange, 10),
            (self.removeFirst, 10),
            (self.removeNFirst, 10),
            (self.mutateSubrange, 10),
            (self.replaceCompletely, 1)
        ]
        */
        return haveRepeatingVariant// + repeatingVariants// + others
    }()
    
    static func repeatMutator(_ m: @escaping (inout Mutated, inout Rand) -> Bool, count: @escaping (inout Rand, Int) -> Int) -> (inout Mutated, inout Rand) -> Bool {
        return { (x: inout Mutated, r: inout Rand) -> Bool in
            var res = false
            for _ in 0 ..< count(&r, x.count) { // don't use uniform distribution, favor lower values
                let res2 = m(&x, &r)
                res = res || res2
            }
            return res
        }
    }
}
