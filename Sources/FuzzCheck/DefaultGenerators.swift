
public struct IntegerFuzzingMutators <T: FixedWidthInteger & RandomInitializable> : FuzzerInputMutatorGroup {
    public typealias Input = T
    
    public enum Mutator {
        case nudge
        case random
        case special
    }
    
    public func mutate(_ input: inout Input, with mutator: Mutator, _ rand: inout FuzzerPRNG) -> Bool {
        switch mutator {
        case .nudge:
            return nudge(&input, &rand)
        case .random:
            return random(&input, &rand)
        case .special:
            return special(&input, &rand)
        }
    }
    
    func nudge(_ x: inout Input, _ r: inout FuzzerPRNG) -> Bool {
        let nudge = Input(r.next(upperBound: 10 as UInt))
        let op: (Input, Input) -> Input = Bool.random(using: &r) ? (&-) : (&+)
        x = op(x, nudge)
        return true
    }
    
    func random(_ x: inout Input, _ r: inout FuzzerPRNG) -> Bool {
        x = T.random(using: &r)
        return true
    }
    
    func special(_ x: inout Input, _ r: inout FuzzerPRNG) -> Bool {
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

extension FuzzerInputGenerator {
    public func initialInputs(_ r: inout FuzzerPRNG) -> [Input] {
        return (0 ..< 10).map { i in
            var x = baseInput
            for _ in 0 ..< (i * 10) {
                _ = mutate(&x, &r)
            }
            return x
        }
    }
}

public struct IntegerFuzzing <T: FixedWidthInteger & RandomInitializable> : FuzzerInputGenerator, FuzzerInputProperties {
    
    let mutators = IntegerFuzzingMutators<T>()
    public let baseInput = 0 as T
    
    public init() { }
    
    public func mutate(_ x: inout T, _ r: inout FuzzerPRNG) -> Bool {
        return mutators.mutate(&x, &r)
    }

    public static func hash(of input: T) -> Int {
        return input.hashValue
    }
    public static func complexity(of: T) -> Double {
        return Double(T.bitWidth) / 8
    }
}

public struct ArrayMutators <M: FuzzerInputMutatorGroup> : FuzzerInputMutatorGroup {
    public typealias Input = Array<M.Input>
    
    public let initializeElement: (inout FuzzerPRNG) -> M.Input
    public let elementMutators: M
    
    public init(initializeElement: @escaping (inout FuzzerPRNG) -> M.Input, elementMutators: M) {
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
    
    public func mutate(_ input: inout Array<M.Input>, with mutator: ArrayMutators<M>.Mutator, _ rand: inout FuzzerPRNG) -> Bool {
        switch mutator {
        case .appendNew:
            return appendNew(&input, &rand)
        case .appendRecycled:
            return appendRecycled(&input, &rand)
        case .insertNew:
            return insertNew(&input, &rand)
        case .insertRecycled:
            return insertRecycled(&input, &rand)
        case .mutateElement:
            return mutateElement(&input, &rand)
        case .swap:
            return swap(&input, &rand)
        case .removeLast:
            return removeLast(&input, &rand)
        case .removeRandom:
            return removeRandom(&input, &rand)
        }
    }
    
    func appendNew(_ x: inout Input, _ r: inout FuzzerPRNG) -> Bool {
        x.append(initializeElement(&r))
        return true
    }
    
    func appendRecycled(_ x: inout Input, _ r: inout FuzzerPRNG) -> Bool {
        guard !x.isEmpty else { return false }
        let y = x.randomElement(using: &r)!
        x.append(y)
        return true
    }
    
    func insertNew(_ x: inout Input, _ r: inout FuzzerPRNG) -> Bool {
        guard !x.isEmpty else { return false }
        let i = x.indices.randomElement(using: &r)!
        x.insert(initializeElement(&r), at: i)
        return true
    }
    
    func insertRecycled(_ x: inout Input, _ r: inout FuzzerPRNG) -> Bool {
        guard !x.isEmpty else { return false }
        let y = x.randomElement(using: &r)!
        let i = x.indices.randomElement(using: &r)!
        x.insert(y, at: i)
        return true
    }
    
    func removeLast(_ x: inout Input, _ r: inout FuzzerPRNG) -> Bool {
        guard !x.isEmpty else { return false }
        x.removeLast()
        return true
    }
    
    func removeFirst(_ x: inout Input, _ r: inout FuzzerPRNG) -> Bool {
        guard !x.isEmpty else { return false }
        x.removeFirst()
        return true
    }
    
    func removeRandom(_ x: inout Input, _ r: inout FuzzerPRNG) -> Bool {
        guard !x.isEmpty else { return false }
        x.remove(at: x.indices.randomElement(using: &r)!)
        return true
    }
    
    func swap(_ x: inout Input, _ r: inout FuzzerPRNG) -> Bool {
        
        guard x.count > 1 else { return false }
        let (i, j) = (x.indices.randomElement(using: &r)!, x.indices.randomElement(using: &r)!)
        x.swapAt(i, j)
        return i != j
    }
    
    func mutateElement(_ x: inout Input, _ r: inout FuzzerPRNG) -> Bool {
        
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
