//
//  ArrayFuzzerGenerator.swift
//  FuzzCheck
//

extension Double {
    static func randomRatioBiasedToZero <R: RandomNumberGenerator> (bias: UInt8, using r: inout R) -> Double {
        var result: Double = 1.0
        for _ in 0 ..< bias {
            result *= Double.random(in: 0 ..< 1.0, using: &r)
        }
        return result
    }
}

public struct ArrayFuzzerGenerator <G: FuzzerInputGenerator> : FuzzerInputGenerator {
    public typealias Input = [G.Input]
    
    let elementGenerator: G
    var mutators: ArrayMutators<G.Input>

    public let baseInput: Input = []
    
    public func newInput(maxComplexity: Double, _ rand: inout FuzzerPRNG) -> Input {
        guard maxComplexity > 0 else { return [] }
        let targetComplexity = Double.random(in: 0 ..< maxComplexity, using: &rand)
        var a: Input = []
        var currentComplexity = ArrayFuzzerGenerator.complexity(of: a)
        while true {
            _ = mutators.mutate(&a, with: .appendNew, spareComplexity: targetComplexity - currentComplexity, &rand)
            currentComplexity = ArrayFuzzerGenerator.complexity(of: a)
            
            while currentComplexity >= targetComplexity {
                _ = mutators.mutate(&a, with: .removeRandom, spareComplexity: 0, &rand)
                currentComplexity = ArrayFuzzerGenerator.complexity(of: a)
                if currentComplexity <= targetComplexity {
                    a.shuffle()
                    return a
                }
            }
            
        }
    }
    
    public init(_ elementGenerator: G) {
        self.elementGenerator = elementGenerator
                
        self.mutators = ArrayMutators(
            initializeElement: { [elementGenerator] c, r in
                elementGenerator.newInput(maxComplexity: c, &r)
            },
            mutateElement: elementGenerator.mutate
        )
    }
    
    public func mutate(_ input: inout Input, _ spareComplexity: Double, _ rand: inout FuzzerPRNG) -> Bool {
        return mutators.mutate(&input, spareComplexity, &rand)
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
    
    public let initializeElement: (Double, inout FuzzerPRNG) -> Element
    public let mutateElement: (inout Element, Double, inout FuzzerPRNG) -> Bool
    
    public init(initializeElement: @escaping (Double, inout FuzzerPRNG) -> Element, mutateElement: @escaping (inout Element, Double, inout FuzzerPRNG) -> Bool) {
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
    
    public func mutate(_ input: inout Array<Element>, with mutator: Mutator, spareComplexity: Double, _ rand: inout FuzzerPRNG) -> Bool {
        
        switch mutator {
        case .appendNew:
            let additionalComplexity = (Double.randomRatioBiasedToZero(bias: 4, using: &rand) * spareComplexity).rounded(.up)
            input.append(initializeElement(additionalComplexity, &rand))
            return true
        case .appendRecycled:
            guard !input.isEmpty else { return false }
            let y = input.randomElement(using: &rand)!
            input.append(y)
            return true
        case .insertNew:
            guard !input.isEmpty else {
                return mutate(&input, with: .appendNew, spareComplexity: spareComplexity, &rand)
            }
            let additionalComplexity = (Double.randomRatioBiasedToZero(bias: 4, using: &rand) * spareComplexity).rounded(.up)
            let i = input.indices.randomElement(using: &rand)!
            input.insert(initializeElement(additionalComplexity, &rand), at: i)
            return true
        case .insertRecycled:
            guard !input.isEmpty else { return false }
            let y = input.randomElement(using: &rand)!
            let i = input.indices.randomElement(using: &rand)!
            input.insert(y, at: i)
            return true
        case .mutateElement:
            guard !input.isEmpty else { return false }
            let i = input.indices.randomElement(using: &rand)!
            return mutateElement(&input[i], spareComplexity, &rand)
        case .swap:
            guard input.count > 1 else { return false }
            let (i, j) = (input.indices.randomElement(using: &rand)!, input.indices.randomElement(using: &rand)!)
            input.swapAt(i, j)
            return i != j
        case .removeLast:
            guard !input.isEmpty else { return false }
            input.removeLast()
            return true
        case .removeRandom:
            guard !input.isEmpty else { return false }
            input.remove(at: input.indices.randomElement(using: &rand)!)
            return true
        }
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

