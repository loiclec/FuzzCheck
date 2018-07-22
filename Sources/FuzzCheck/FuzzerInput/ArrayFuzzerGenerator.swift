//
//  ArrayFuzzerGenerator.swift
//  FuzzCheck
//

public struct ArrayFuzzerGenerator <G: FuzzerInputGenerator> : FuzzerInputGenerator {
    public typealias Input = [G.Input]
    
    let elementGenerator: G
    var mutators: ArrayMutators<G.Input>

    public let baseInput: Input = []
    
    public func newInput(maxComplexity: Double, _ rand: inout FuzzerPRNG) -> Input {
        
        let targetComplexity = Double.random(in: 1 ..< maxComplexity, using: &rand)
        var a: Input = []
        while true {
            _ = mutate(&a, &rand)
            if ArrayFuzzerGenerator.complexity(of: a) >= targetComplexity {
                _ = mutators.removeRandom(&a, &rand)
                return a
            }
        }
    }
    
    public init(maxComplexity: Double, _ elementGenerator: G) {
        self.elementGenerator = elementGenerator
                
        self.mutators = ArrayMutators.init(
            initializeElement: { [elementGenerator] r in
                elementGenerator.newInput(maxComplexity: 0.0 /* FIXME */, &r)
            },
            mutateElement: elementGenerator.mutate
        )
    }
    
    public func mutate(_ input: inout Input, _ rand: inout FuzzerPRNG) -> Bool {
        return mutators.mutate(&input, &rand)
    }
    
    public typealias CodableInput = [G.CodableInput]
    
    public static func complexity(of input: Input) -> Double {
        return input.reduce(0) { $0 + G.complexity(of: $1) }
    }
    public static func hash(_ input: Input, into hasher: inout Hasher) {
        for x in input {
            G.hash(x, into: &hasher)
        }
    }
    public static func convertToCodable(_ input: Input) -> CodableInput {
        return input.map(G.convertToCodable)
    }
    public static func convertFromCodable(_ codable: CodableInput) -> Input {
        return codable.map(G.convertFromCodable)
    }
}

public struct ArrayMutators <Element> : FuzzerInputMutatorGroup {
    
    public typealias Input = Array<Element>
    
    public let initializeElement: (inout FuzzerPRNG) -> Element
    public let mutateElement: (inout Element, inout FuzzerPRNG) -> Bool
    
    public init(initializeElement: @escaping (inout FuzzerPRNG) -> Element, mutateElement: @escaping (inout Element, inout FuzzerPRNG) -> Bool) {
        self.initializeElement = initializeElement
        self.mutateElement = mutateElement
    }
    
    public enum Mutator {
        case appendNew
        // TODO: appendRecycled should not exist. Instead, appendNew
        // should initialize its element from a pool that may include
        // recycled ones
        case appendRecycled
        case insertNew
        case insertRecycled
        // TODO: the probability of picking mutateElement should depend on
        // the size of the array. Or maybe even from the relative complexity
        // of the element. And maybe from the maximum allowed complexity.
        // This is something that we get for free when using binary
        // buffers with libFuzzer but is more difficult to achieve
        // for typed values in FuzzCheck
        case mutateElement
        // TODO: generalize to swapping subsequences
        case swap
        case removeLast
        case removeRandom
        // TODO: append/insert repeated?
        // TODO: duplicate subsequence?
        // TODO: rotate, partition, sort?
        // TODO: a way to configure the array mutators so I don't have to pick
        // one set of tradeoffs for all possible situations
    }
    
    public func mutate(_ input: inout Array<Element>, with mutator: Mutator, _ rand: inout FuzzerPRNG) -> Bool {
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
        return mutateElement(&x[i], &r)
    }
    
    public let weightedMutators: [(Mutator, UInt)] = [
        // TODO: this is completely arbitrary
        // I should find a better way to determine the
        // correct weights
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

